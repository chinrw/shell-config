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

  # ── Passwordless sudo for docker (chin39, container CLI fallback) ─
  # In container mode, the hermes-agent container runs under rootful
  # docker (because services.hermes-agent.service runs as root and
  # uses the system docker socket /var/run/docker.sock). chin39's
  # interactive shell uses ROOTLESS docker (per
  # virtualisation.docker.rootless.setSocketVariable = true in
  # nixos/configuration.nix:99-104), so chin39's `docker` commands
  # cannot see the hermes-agent container. Hermes' CLI detects this
  # and falls back to `sudo -n docker exec` — but only if sudo is
  # passwordless. This rule scopes that to /run/current-system/sw/bin/docker
  # only; chin39 still needs full sudo for everything else.
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
      # Primary model: local llama.cpp on the LAN.
      # ${LOCAL_MODEL_NAME} resolves at gateway startup from the
      # .env file. The probe (below) writes that variable into the
      # bind-mounted .env on every service start, so swapping a GGUF
      # on the Windows box + `sudo systemctl restart hermes-agent`
      # is enough to pick up the new model — no nixos-rebuild needed.
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

      model_aliases = {
        deepseek = {
          model = deepseekModel;
          provider = "deepseek";
        };
        local = {
          model = "\${LOCAL_MODEL_NAME}";
          provider = "custom";
          base_url = "${llamaEndpoint}/v1";
        };
      };

      # Named custom providers — makes the local llama.cpp endpoint show
      # up in the `hermes model` and `/model` pickers as a selectable
      # entry. Without this the picker only enumerates built-in cloud
      # providers; the bare `model.base_url` above wires the runtime
      # default but isn't discoverable through the UI. Reference:
      # hermes_cli/config.py:2859 (get_compatible_custom_providers).
      # Switch syntax: /model custom:local:<model-name>
      custom_providers = [
        {
          name = "local";
          base_url = "${llamaEndpoint}/v1";
          # api_key omitted — keyless local llama.cpp server
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
  # Probe llama.cpp on the host before each container start; write
  # LOCAL_MODEL_NAME directly into /var/lib/hermes/.hermes/.env
  # (which the container sees as /data/.hermes/.env via the bind
  # mount). The container's gateway re-reads .env on startup and
  # picks up the new value. Idempotent: sed-deletes any prior
  # LOCAL_MODEL_NAME line before appending fresh.
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
}
