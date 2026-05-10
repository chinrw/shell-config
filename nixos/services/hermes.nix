{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  deepseekModel = "deepseek-v4-flash";
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  # ── Sops secret: hermes-env ─────────────────────────────────────
  # Encrypted dotenv file at secrets/hermes.env. sops-nix decrypts
  # at activation (running as root, reading chin39's user age key)
  # and writes plaintext to /run/secrets/hermes-env owned by the
  # hermes service user.
  # TODO(Task 5): Uncomment after secrets/hermes.env is encrypted and committed.
  # sops.secrets."hermes-env" = {
  #   sopsFile = ../../secrets/hermes.env;
  #   format = "dotenv";
  #   owner = "hermes";
  #   mode = "0400";
  # };

  # ── Service ─────────────────────────────────────────────────────
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;

    environmentFiles = [
      # TODO(Task 5): Re-add after secrets/hermes.env is encrypted and committed.
      # config.sops.secrets."hermes-env".path
      "/run/hermes/discovered.env"
    ];

    settings = {
      # Primary model: local llama.cpp on the LAN.
      # Model name discovered at service start by the probe below;
      # do not hardcode it. Swap GGUFs on the server, restart hermes.
      model = {
        default = "\${LOCAL_MODEL_NAME}";
        provider = "custom";
        base_url = "http://192.168.0.101:8087/v1";
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
          base_url = "http://192.168.0.101:8087/v1";
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
      # Parity with hermes' upstream dev shell
      python312
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

    extraPythonPackages = with pkgs.python312Packages; [
      requests
      beautifulsoup4
      httpx
      pydantic
    ];

    restart = "always";
    restartSec = 5;
  };

  # ── Systemd overrides: probe llama.cpp for the live model name ──
  # Runs before the gateway. 5s timeout, graceful fallback writes
  # LOCAL_MODEL_NAME=local-unavailable so the service still starts
  # when the model server is asleep.
  systemd.services.hermes-agent = {
    serviceConfig.RuntimeDirectory = "hermes";
    serviceConfig.RuntimeDirectoryMode = "0750";
    serviceConfig.ExecStartPre = [
      (pkgs.writeShellScript "hermes-probe-local-model" ''
        set -u
        OUT=/run/hermes/discovered.env

        MODEL=$(${pkgs.curl}/bin/curl -fsS --max-time 5 \
          http://192.168.0.101:8087/v1/models 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '.data[0].id // empty' 2>/dev/null \
          || true)

        if [ -z "$MODEL" ]; then
          MODEL="local-unavailable"
          echo "[hermes-probe] llama.cpp unreachable; LOCAL_MODEL_NAME=$MODEL" >&2
        else
          echo "[hermes-probe] LOCAL_MODEL_NAME=$MODEL" >&2
        fi

        umask 077
        printf 'LOCAL_MODEL_NAME=%s\n' "$MODEL" > "$OUT"
        chown hermes:hermes "$OUT"
        chmod 0440 "$OUT"
      '')
    ];
  };
}
