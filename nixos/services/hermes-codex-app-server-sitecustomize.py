"""Bridge Hermes model switches into Codex app-server turns.

Hermes 7cb2d2c selects ``codex_app_server`` as a transport, but its
``turn/start`` request does not forward the live agent model or reasoning
effort.  That makes ``/model`` update Hermes' banner while Codex keeps using
the model from its own config.toml.  Codex app-server 0.144.5 supports both
fields as per-turn overrides, so inject them at the transport boundary.

Also remaps the picker's ``openai-api`` row to ``openai-codex`` so picking
a GPT model bills the ChatGPT subscription instead of the per-token OpenAI
API.

This is loaded through PYTHONPATH as ``sitecustomize``.  Keep it deliberately
small and remove it once upstream Hermes forwards these fields itself.
"""

from __future__ import annotations

import os
from contextvars import ContextVar
from typing import Any, NamedTuple


class _TurnSelection(NamedTuple):
    model: str
    effort: str


_active_selection: ContextVar[_TurnSelection] = ContextVar(
    "hermes_codex_selection", default=_TurnSelection(model="", effort="")
)


def _install_bridge() -> None:
    from agent import codex_runtime
    from agent.transports import codex_app_server

    if getattr(codex_runtime, "_nixos_model_bridge_installed", False):
        return

    original_turn = codex_runtime.run_codex_app_server_turn
    original_request = codex_app_server.CodexAppServerClient.request

    def run_turn_with_selection(agent: Any, *args: Any, **kwargs: Any) -> Any:
        model = str(getattr(agent, "model", "") or "").strip()
        reasoning = getattr(agent, "reasoning_config", None)
        effort = ""
        if isinstance(reasoning, dict):
            if reasoning.get("enabled") is False:
                effort = "none"
            else:
                effort = str(reasoning.get("effort", "") or "").strip().lower()

        token = _active_selection.set(_TurnSelection(model=model, effort=effort))
        try:
            return original_turn(agent, *args, **kwargs)
        finally:
            _active_selection.reset(token)

    def request_with_selection(
        self: Any,
        method: str,
        params: dict[str, Any] | None = None,
        timeout: float = 30.0,
    ) -> dict[str, Any]:
        if method == "turn/start":
            params = dict(params or {})
            selection = _active_selection.get()
            if selection.model:
                params["model"] = selection.model
            if selection.effort:
                params["effort"] = selection.effort
        return original_request(self, method, params, timeout)

    codex_runtime.run_codex_app_server_turn = run_turn_with_selection
    codex_app_server.CodexAppServerClient.request = request_with_selection
    codex_runtime._nixos_model_bridge_installed = True


def _fix_codex_picker_slug() -> None:
    from hermes_cli import model_switch

    original_list = model_switch.list_authenticated_providers

    # Both the gateway picker (list_picker_providers) and the TUI inventory
    # (hermes_cli/inventory.py) build their rows here, labelling the
    # codex-backed row with its models.dev id "openai-api" — but switching
    # with that slug resolves to the per-token api.openai.com provider, not
    # the ChatGPT-subscription OAuth route the row's models came from.
    # Rewrite the slug at the source so every picker routes through
    # openai-codex.
    def list_with_codex_slug(*args: Any, **kwargs: Any) -> Any:
        rows = list(original_list(*args, **kwargs))
        # With an OPENAI_API_KEY present an "openai-api" row may be the real
        # per-token provider — leave everything alone rather than relabel it.
        if os.environ.get("OPENAI_API_KEY"):
            return rows
        # OAuth row already listed under its own slug — nothing to fix.
        if any(r.get("slug") == "openai-codex" for r in rows):
            return rows
        # No API key: any openai-api row is the OAuth backend in disguise.
        current = str(
            kwargs.get("current_provider") or (args[0] if args else "") or ""
        ).strip().lower()
        out = []
        for row in rows:
            if row.get("slug") == "openai-api":
                row = {**row, "slug": "openai-codex", "name": "OpenAI (ChatGPT)"}
                if current == "openai-codex":
                    row["is_current"] = True
            out.append(row)
        return out

    model_switch.list_authenticated_providers = list_with_codex_slug


def _warn_bridge_broken(exc: Exception) -> None:
    import logging

    logging.getLogger("hermes_codex_bridge").warning(
        "codex app-server model bridge not installed; live /model and "
        "reasoning-effort switches will not reach Codex: %s",
        exc,
    )


try:
    _install_bridge()
except ImportError as exc:
    from importlib.util import find_spec

    # Non-hermes Python entry points lack the agent package — skip silently.
    # If agent IS importable, the pinned layout changed: warn, don't hide.
    if find_spec("agent") is not None:
        _warn_bridge_broken(exc)
except AttributeError as exc:
    # agent imported, but a patched call site was renamed or moved.
    _warn_bridge_broken(exc)

try:
    _fix_codex_picker_slug()
except ImportError:
    # Absent hermes_cli means a non-hermes interpreter.
    pass
