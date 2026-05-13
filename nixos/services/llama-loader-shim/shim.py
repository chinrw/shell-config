"""llama-loader-shim — transparent /models/load injector.

Sits between a client (Hermes) and an upstream llama.cpp server started
with ``--no-models-autoload`` + ``--models-max 1``. For every POST to
/v1/chat/completions or /v1/completions, the shim parses out the
``model`` field and issues ``POST /models/load`` on the upstream first
so chat requests stop returning HTTP 400 ``model is not loaded``.

State caching: we remember the last successful load and skip the load
call when consecutive requests target the same model. When the upstream
disagrees with our cache (server restarted, ``--sleep-idle-seconds``
evicted, etc.), the first 400 ``model is not loaded`` invalidates the
cache and triggers one forced retry — so the user-visible failure mode
collapses from "every switch breaks" to "at most one stale request per
eviction".

All non-load paths (notably ``/v1/models``) pass through unchanged,
preserving headers and streaming response bodies.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os

from aiohttp import ClientSession, ClientTimeout, web

UPSTREAM = os.environ.get("UPSTREAM_URL", "http://192.168.0.101:8087").rstrip("/")
BIND_HOST = os.environ.get("BIND_HOST", "0.0.0.0")
BIND_PORT = int(os.environ.get("BIND_PORT", "8088"))
LOAD_TIMEOUT = float(os.environ.get("LOAD_TIMEOUT", "120"))

LOAD_PATHS = {"/v1/chat/completions", "/v1/completions"}
HOP_HEADERS = {"host", "content-length", "transfer-encoding", "connection"}

state: dict[str, str | None] = {"loaded": None}
load_lock = asyncio.Lock()
log = logging.getLogger("llama-loader-shim")


async def ensure_loaded(session: ClientSession, model: str) -> None:
    """POST /models/load if our cache doesn't already say `model` is up.

    Silent on failure — the subsequent forward will surface the actual
    upstream error to the client.
    """
    async with load_lock:
        if state["loaded"] == model:
            return
        try:
            async with session.post(
                f"{UPSTREAM}/models/load",
                json={"model": model},
                timeout=ClientTimeout(total=LOAD_TIMEOUT),
            ) as resp:
                if resp.status == 200:
                    data = await resp.json()
                    if data.get("success") is True:
                        state["loaded"] = model
                        log.info("loaded %s", model)
                        return
                log.warning("/models/load %s -> HTTP %d", model, resp.status)
        except Exception as exc:
            log.warning("/models/load %s failed: %s", model, exc)


def _passthrough(headers) -> dict[str, str]:
    return {k: v for k, v in headers.items() if k.lower() not in HOP_HEADERS}


async def _forward(
    request: web.Request,
    session: ClientSession,
    model: str | None,
    retried: bool = False,
) -> web.StreamResponse:
    body = request["body"]
    async with session.request(
        request.method,
        f"{UPSTREAM}{request.path}",
        params=request.rel_url.query,
        headers=_passthrough(request.headers),
        data=body,
        # No timeout — chat completions may stream for minutes.
        timeout=ClientTimeout(total=None),
    ) as upstream:
        # When the upstream rejects with "model is not loaded" despite
        # our cache, treat the cache as stale, force a load, and retry
        # once. Error bodies are small JSON, so reading them up front
        # is fine.
        if upstream.status == 400 and model and not retried:
            err = await upstream.read()
            try:
                msg = json.loads(err).get("message", "")
            except (json.JSONDecodeError, AttributeError):
                msg = ""
            if "not loaded" in msg:
                log.info("cache invalidate: server says %s not loaded", model)
                state["loaded"] = None
                await ensure_loaded(session, model)
                return await _forward(request, session, model, retried=True)
            return web.Response(
                status=400,
                body=err,
                headers=_passthrough(upstream.headers),
            )

        response = web.StreamResponse(
            status=upstream.status,
            headers=_passthrough(upstream.headers),
        )
        await response.prepare(request)
        async for chunk in upstream.content.iter_any():
            await response.write(chunk)
        await response.write_eof()
        return response


async def handle(request: web.Request) -> web.StreamResponse:
    request["body"] = await request.read()
    session: ClientSession = request.app["session"]

    model: str | None = None
    if request.method == "POST" and request.path in LOAD_PATHS:
        try:
            payload = json.loads(request["body"]) if request["body"] else {}
            model = payload.get("model")
        except (json.JSONDecodeError, AttributeError):
            pass
        if isinstance(model, str) and model:
            await ensure_loaded(session, model)
        else:
            model = None

    return await _forward(request, session, model)


async def on_startup(app: web.Application) -> None:
    app["session"] = ClientSession()


async def on_cleanup(app: web.Application) -> None:
    await app["session"].close()


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    app = web.Application()
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    app.router.add_route("*", "/{path:.*}", handle)
    web.run_app(app, host=BIND_HOST, port=BIND_PORT, access_log=None)


if __name__ == "__main__":
    main()
