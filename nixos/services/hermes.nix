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
