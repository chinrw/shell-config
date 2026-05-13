{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  deepseekModel = "deepseek-v4-flash";
  llamaEndpoint = "http://192.168.0.101:8087";
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
      # Primary model: local llama.cpp on the LAN (multi-model, lazy-load).
      # ${LOCAL_MODEL_NAME} is the boot-time default — the probe (below)
      # writes the first id from /v1/models into .env. Runtime switching
      # between any of the models that llama-swap exposes happens via
      # `/model custom:local:<name>`; the picker enumerates them live
      # (see custom_providers.discover_models below). When the local
      # endpoint is unreachable or returns an error, fallback_providers
      # (DeepSeek) takes over automatically.
      model = {
        default = "\${LOCAL_MODEL_NAME}";
        provider = "custom";
        base_url = "${llamaEndpoint}/v1";
        api_key = "\${OPENAI_API_KEY}";
      };

      # Compression: DeepSeek named provider (built-in base_url +
      # DEEPSEEK_API_KEY env var; no extra wiring needed).
      auxiliary.compression = {
        provider = "deepseek";
        model = deepseekModel;
        timeout = 30;
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
      # Hermes hits /v1/models on demand and enumerates every GGUF
      # llama-swap is currently serving (see hermes_cli/model_switch.py:
      # the discovery branch is gated on `api_url && api_key && discover`).
      # llama.cpp is keyless, but Hermes needs a non-empty Bearer to
      # trigger the live fetch; the value itself is ignored upstream.
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

    restart = "always";
    restartSec = 5;
  };

  # ── Runtime model probe ─────────────────────────────────────────
  # Picks the boot-time default model for `model.default` only.
  # Live switching between the other models llama-swap is serving
  # goes through the `/model` picker (custom_providers.discover_models
  # makes them enumerable). If the probe fails (llama.cpp down, empty
  # /v1/models, etc.), the placeholder "local-unavailable" gets written;
  # the first chat request then errors out and fallback_providers
  # (DeepSeek) takes over — no special handling needed here.
  #
  # Writes LOCAL_MODEL_NAME into /var/lib/hermes/.hermes/.env (the
  # container sees this as /data/.hermes/.env via bind mount). The
  # gateway re-reads .env on startup. Idempotent: sed-deletes any
  # prior LOCAL_MODEL_NAME before appending.
  #
  # Self-healing: nixos-rebuild's activation script overwrites .env
  # by re-merging environmentFiles — wiping our probe addition. The
  # NEXT service start re-runs ExecStartPre which re-adds the line,
  # so the system converges back to a correct state automatically.
  systemd.services.hermes-agent.serviceConfig.ExecStartPre = [
    (pkgs.writeShellScript "hermes-probe-local-model" ''
      set -u
      ENV_FILE=/var/lib/hermes/.hermes/.env

      MODEL=$(${pkgs.curl}/bin/curl -fsS --max-time 5 \
        ${llamaEndpoint}/v1/models 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r '.data[0].id // empty' 2>/dev/null \
        || true)

      if [ -z "$MODEL" ]; then
        MODEL="local-unavailable"
        echo "[hermes-probe] llama.cpp unreachable; LOCAL_MODEL_NAME=$MODEL" >&2
      else
        echo "[hermes-probe] LOCAL_MODEL_NAME=$MODEL" >&2
      fi

      if [ -f "$ENV_FILE" ]; then
        ${pkgs.gnused}/bin/sed -i '/^LOCAL_MODEL_NAME=/d' "$ENV_FILE"
      fi
      echo "LOCAL_MODEL_NAME=$MODEL" >> "$ENV_FILE"
    '')
  ];

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
