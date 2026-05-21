{
  config,
  pkgs,
  inputs,
  ...
}:
let
  deepseekModel = "deepseek-v4-flash";

  # Local llama.cpp endpoint — points at the loader-shim
  # (services/llama-loader-shim.nix) on this host, NOT directly at the
  # llama-server on the Windows box. The shim transparently injects a
  # POST /models/load before every chat/completion, working around
  # llama-server's --no-models-autoload + --models-max 1. Bypassing
  # the shim (going straight to 192.168.0.101:8087) means /model
  # switches no longer "just work" — they 400 on every cold model.
  #
  # The primary chat model is DeepSeek (see settings.model below); the
  # shim now serves only the delegation subagents and the local-pinned
  # auxiliary roles. Loopback works because hermes-agent's upstream
  # module pins the container to `--network=host` (see
  # nix/nixosModules.nix:942), so 127.0.0.1 inside the container is this
  # host's loopback. NO_PROXY already excludes 127.0.0.1 from the xray hop.
  llamaEndpoint = "http://127.0.0.1:8088";

  # The local GGUF every local consumer shares. Must match a section
  # name (or alias) in the server-side models.ini — currently "default"
  # is aliased there to the opus-distill GGUF.
  preferredLocalModel = "default";

  # Shared target for everything routed to the local llama.cpp: the
  # delegation subagents and the local-pinned auxiliary roles. Pinning
  # every local consumer to ONE GGUF (preferredLocalModel) means the
  # shim's single model slot (--models-max 1) never thrashes between
  # loads. api_key is a dummy — llama-server is keyless.
  localTarget = {
    base_url = "${llamaEndpoint}/v1";
    api_key = "\${OPENAI_API_KEY}";
    model = preferredLocalModel;
  };

  # Auxiliary variant: same local target plus a roomier timeout. The
  # auxiliary default of 30s can fire mid-load when the shim cold-loads
  # the GGUF (the upstream schema itself flags "increase for slow local
  # models"). delegation has no `timeout` key, so it stays on localTarget.
  localAuxTarget = localTarget // { timeout = 60; };
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  security.sudo.extraRules = [
    {
      users = [ "chin39" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/docker";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # ── Sops secret: hermes-env ─────────────────────────────────────
  # Encrypted dotenv file at secrets/hermes.env. sops-nix decrypts
  # at activation (running as root, reading chin39's user age key)
  # and writes plaintext to /run/secrets/hermes-env owned by the
  # hermes service user.
  sops.secrets."hermes-env" = {
    sopsFile = ../../secrets/hermes.env;
    format = "dotenv";
    owner = "hermes";
    mode = "0400";
  };

  # ── Service ─────────────────────────────────────────────────────
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;

    # Run hermes inside an Ubuntu 24.04 container. With both
    # container.enable and addToSystemPackages = true, the binary
    # installed on chin39's PATH is the upstream CLI ROUTER, not
    # the real hermes — every invocation docker-execs into this
    # container and runs as the container's hermes user. That
    # eliminates the user-mismatch collisions the previous
    # native-mode setup suffered from.
    container = {
      enable    = true;
      backend   = "docker";
      image     = "ubuntu:24.04";
      hostUsers = [ "chin39" ];

      # Proxy env passed via `docker create --env` so it lands in the
      # container's PID 1 environ from process startup — visible to
      # any library (including python-telegram-bot's httpx layer) that
      # captures proxy config at import time. Setting these via
      # services.hermes-agent.environment was insufficient because
      # those go through the merged .env file, which is only loaded
      # after Python has already imported telegram/httpx and cached
      # the proxy config.
      #
      # NO_PROXY exempts:
      #   - 192.168.0.0/24 — local LAN (mirrors host config)
      #   - 127.0.0.1 / localhost — loopback
      #   - api.deepseek.com — direct-reachable from CN; bypass proxy
      extraOptions = [
        "--env" "HTTP_PROXY=http://192.168.0.240:10809"
        "--env" "HTTPS_PROXY=http://192.168.0.240:10809"
        "--env" "NO_PROXY=192.168.0.0/24,127.0.0.1,localhost,api.deepseek.com"
        "--env" "TELEGRAM_PROXY=http://192.168.0.240:10809"
      ];
    };

    environmentFiles = [
      config.sops.secrets."hermes-env".path
    ];

    settings = {
      # Primary chat model: DeepSeek deepseek-v4-flash. `provider:
      # "deepseek"` is a built-in named provider — it ships a hardcoded
      # base_url (https://api.deepseek.com/v1) and reads DEEPSEEK_API_KEY
      # from the env, so no base_url/api_key wiring is needed here. The
      # orchestrator runs on this model and hands simpler sub-steps down
      # to local subagents via `delegation` below. When DeepSeek errors
      # out (5xx/timeout/rate-limit), fallback_providers takes over.
      model = {
        default = deepseekModel;
        provider = "deepseek";
      };

      # Subagent delegation — delegate_task spawns child agents on the
      # LOCAL llama.cpp (via the loader-shim), not on the primary. This
      # is the cheap executor tier: the DeepSeek orchestrator does the
      # hard reasoning and delegates simpler sub-tasks to local
      # subagents. delegate_tool.py uses delegation.base_url verbatim
      # when set; `model` must be explicit, or an empty value would
      # inherit the parent's "deepseek-v4-flash" name and send it to the
      # local server, which does not know that name.
      delegation = localTarget;

      # Auxiliary side-task models. Hermes' `auxiliary` namespace exists
      # to keep chores OFF the expensive path. Every auxiliary role's
      # upstream schema comment recommends a cheap/fast model — none call
      # for a strong one — so nothing here uses a Pro tier.
      #
      # The four below run on the local llama.cpp: tiny, high-frequency,
      # privacy-sensitive chores that fit the local server's per-slot
      # context. Same GGUF as delegation, so the shim's single slot never
      # thrashes. web_extract, triage_specifier, approval, curator and
      # vision are left unset — provider "auto" makes them follow the
      # primary (DeepSeek flash); they are large-context or capability-
      # sensitive, so deliberately not pinned local.
      auxiliary = {
        title_generation = localAuxTarget;
        session_search = localAuxTarget;
        skills_hub = localAuxTarget;
        mcp = localAuxTarget;

        # Compression summarises very large contexts — the local
        # server's ~51k per-slot window would overflow — so it stays on
        # DeepSeek flash (named provider: built-in base_url +
        # DEEPSEEK_API_KEY, no extra wiring). Pinned explicitly rather
        # than left "auto" so it stays cheap even if the primary changes.
        compression = {
          provider = "deepseek";
          model = deepseekModel;
          timeout = 30;
        };
      };

      compression = {
        enabled = true;
        threshold = 0.50;
        target_ratio = 0.20;
        protect_last_n = 20;
      };

      # Quick-switch alias for DeepSeek (`/model deepseek`). The local
      # alias was dropped — with multi-model discovery below, every llama
      # model already appears in the picker as `custom:local:<name>`, so
      # a single-model `local` alias would be both redundant and misleading.
      model_aliases = {
        deepseek = {
          model = deepseekModel;
          provider = "deepseek";
        };
      };

      # Named custom providers — exposes the local llama.cpp endpoint to
      # the `/model` picker. With api_key set + discover_models = true,
      # Hermes hits /v1/models on demand and enumerates every section in
      # the server's models.ini (see hermes_cli/model_switch.py: the
      # discovery branch is gated on `api_url && api_key && discover`).
      # llama-server is keyless, but Hermes needs a non-empty Bearer to
      # trigger the live fetch; the value itself is ignored upstream.
      # The shim passes /v1/models through untouched, so discovery
      # reflects the real server-side registry.
      # Switch syntax: /model custom:local:<model-name>
      custom_providers = [
        {
          name = "local";
          base_url = "${llamaEndpoint}/v1";
          api_key = "no-key-required";
          discover_models = true;
        }
      ];

      # Fallback chain — tried in order when the primary model errors out
      # (5xx, timeout, rate-limit, connection refused). Hermes' app-level
      # retry loop walks this list before surfacing the failure to the
      # agent. Reference: hermes_cli/fallback_cmd.py, gateway/run.py:714.
      # Currently deepseek-v4-flash, the same model as the primary — a
      # no-op safety net kept as the explicit slot to repoint later.
      fallback_providers = [
        {
          provider = "deepseek";
          model = deepseekModel;
        }
      ];

      terminal = {
        backend = "local";
        cwd = ".";
        timeout = 180;
      };

      security = {
        tirith_enabled = true;
        tirith_fail_open = false;
      };
    };

    extraPackages = with pkgs; [
      # Parity with hermes' upstream dev shell.
      # python312 deliberately omitted: the sealed uv2nix venv
      # provides Python via $HERMES_PYTHON; adding python312 here
      # would pull python3.12-3.12.13-doc.drv (via
      # environment.extraOutputsToInstall = ["man" "info" "doc"])
      # which fails on a sphinx/docutils-0.22.4 incompatibility.
      uv
      nodejs_22
      ripgrep
      git
      openssh
      ffmpeg

      # Standard agent toolkit
      curl
      wget
      jq
      fd
      yq-go
      tree
      file
      unzip
      gnutar
      gzip

      # Build tooling
      gnumake
      gcc
      pkg-config

      # Shell niceties
      bashInteractive
      coreutils-full
      gnused
      gawk
    ];

    # extraPythonPackages are for user-developed plugins only.
    # requests, httpx, pydantic are already in hermes' sealed
    # uv2nix venv; beautifulsoup4 pulls typing-extensions
    # transitively which collides with the venv. Empty list.
    extraPythonPackages = [ ];

    # Bake the `messaging` extra into the sealed uv2nix venv so the
    # Telegram adapter's `from telegram import …` 
    extraDependencyGroups = [ "messaging" ];

    restart = "always";
    restartSec = 5;
  };

  # Start hermes after the loader-shim. The shim serves the delegation
  # subagents and the local-pinned auxiliary roles (not the primary chat
  # model, which is DeepSeek). Loose ordering only — if the shim is down
  # those local calls fail, but the primary DeepSeek path is unaffected.
  systemd.services.hermes-agent = {
    after = [ "llama-loader-shim.service" ];
    wants = [ "llama-loader-shim.service" ];
  };

  systemd.services.hermes-perm-watch = {
    description = "Reset /var/lib/hermes/.hermes to 2770 on attrib change";
    after = [ "hermes-agent.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
      ExecStart = pkgs.writeShellScript "hermes-perm-watch" ''
        set -u
        D=/var/lib/hermes/.hermes
        # Initial sweep — fix whatever state we booted into.
        [ -d "$D" ] && ${pkgs.coreutils}/bin/chmod 2770 "$D" 2>/dev/null || true
        # Watch for attribute changes (chmod, chown, setxattr).
        # --format '%w' just emits the dir path; we use stat to read
        # the current mode and chmod only when it actually drifted.
        ${pkgs.inotify-tools}/bin/inotifywait -m -e attrib \
          --format '%w' "$D" 2>/dev/null \
          | while IFS= read -r _; do
              cur=$(${pkgs.coreutils}/bin/stat -c '%a' "$D" 2>/dev/null)
              if [ -n "$cur" ] && [ "$cur" != "2770" ]; then
                ${pkgs.coreutils}/bin/chmod 2770 "$D" \
                  && echo "hermes-perm-watch: restored $D to 2770 (was $cur)"
              fi
            done
      '';
    };
  };
}
