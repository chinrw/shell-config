{
  config,
  pkgs,
  inputs,
  ...
}:
let
  # DeepSeek tiers — fallback chain + manual /model deepseek[-flash] only.
  deepseekPro = "deepseek-v4-pro";
  deepseekFlash = "deepseek-v4-flash";

  # Video-capable model for the auxiliary "vision" role (Go plan). The aux
  # path sends whole videos as video_url blocks, which the Codex route does
  # not accept (input_image only) — so this one role stays off Codex.
  kimiVision = "kimi-k2.6";

  # GPT-5.6 models reached through Codex CLI's ChatGPT subscription login.
  # Luna is the high-volume default; Terra and Sol remain explicit /model
  # escalations for tasks that need progressively more capability.
  codexLuna = "gpt-5.6-luna";
  codexTerra = "gpt-5.6-terra";
  codexSol = "gpt-5.6-sol";

  # Empty base_url/api_key overwrite the stale Go-gateway keys the additive
  # config merge would otherwise leave behind when a role moves onto Codex.
  codexTarget = model: {
    provider = "openai-codex";
    inherit model;
    base_url = "";
    api_key = "";
  };

  # ── opencode Zen "Go" plan gateway ──────────────────────────────
  # OpenAI-compatible multi-model endpoint, now only behind the legacy
  # `/model pro` shortcut and the switchable `opencode-go` custom provider.
  # provider "custom" + explicit base_url/api_key is Hermes' generic
  # OpenAI-compatible shape.
  opencodeGoEndpoint = "https://opencode.ai/zen/go/v1";

  goBase = {
    provider = "custom";
    base_url = opencodeGoEndpoint;
    api_key = "\${OPENCODE_API_KEY}";
  };

  # A specific Go-plan model reached through the Go gateway.
  goTarget = model: goBase // { inherit model; };

  # ── Native DeepSeek API (fallback + manual aliases) ──────────────
  # Keep a route independent of the OpenCode Go plan and its credential.
  # This backs the fallback chain on Hermes' default runtime plus the manual
  # `/model deepseek` and `/model deepseek-flash` switches.
  #
  # provider = "deepseek" is hermes' built-in named provider
  # (plugins/model-providers/deepseek): it activates DeepSeekProfile, which
  # emits the extra_body.thinking / reasoning_effort wire shape the V4
  # family requires to avoid the "reasoning_content must be passed back"
  # HTTP 400 trap that a raw custom provider would hit.
  #
  # base_url is pinned explicitly (not left to the provider default) ON
  # PURPOSE: hermes derives the credential from the base_url HOST
  # (runtime_provider.py:_host_derived_api_key — api.deepseek.com →
  # DEEPSEEK_API_KEY), so an empty base_url at resolution time would yield
  # no key and a "Missing API key" 401. Pinning it guarantees the
  # DEEPSEEK_API_KEY env var is picked up. api_key is deliberately left to
  # that host-derivation rather than an explicit "${DEEPSEEK_API_KEY}".
  deepseekApiTarget = model: {
    provider = "deepseek";
    base_url = "https://api.deepseek.com/v1";
    inherit model;
  };

  # Codex aux target with the DeepSeek backstop: when the explicit Codex
  # provider fails or can't build a client, hermes walks the per-task
  # auxiliary.<task>.fallback_chain (auxiliary_client.py:3950).
  codexAuxTarget =
    model:
    (codexTarget model)
    // {
      fallback_chain = [
        (deepseekApiTarget deepseekPro)
        (deepseekApiTarget deepseekFlash)
      ];
    };

  # Compatibility bridge for the pinned Hermes revision: its app-server
  # adapter selects the Codex runtime but does not forward a live /model
  # switch or reasoning effort into turn/start. Codex 0.144.5 supports both
  # fields, so this sitecustomize hook injects them per turn. It also remaps
  # the picker's openai-api row to openai-codex (subscription billing).
  # Remove it once upstream covers these.
  codexAppServerBridge = pkgs.writeTextDir "${pkgs.python312.sitePackages}/sitecustomize.py" (
    builtins.readFile ./hermes-codex-app-server-sitecustomize.py
  );

  # Same codex/claude builds home-manager installs — nix-provided so they
  # survive container recreation (replacing the npm-global copies).
  codexPackage = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  claudePackage = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # ── Dashboard ───────────────────────────────────────────────────
  dashboardPort = 9119;
  dashboardWaitSeconds = 30;
  dashboardCmd = "${pkgs.docker}/bin/docker exec --user hermes hermes-agent /data/current-package/bin/hermes dashboard";
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

  # Dashboard credentials are kept separately from hermes-env. Hermes hashes
  # the plaintext login password in memory when loading the basic-auth plugin;
  # the independent session-signing key keeps sessions valid across restarts.
  sops.secrets."hermes-dashboard-password" = {
    sopsFile = ../../secrets/hermes-dashboard.yaml;
    key = "dashboard/password";
    owner = "hermes";
    mode = "0400";
  };
  sops.secrets."hermes-dashboard-session-secret" = {
    sopsFile = ../../secrets/hermes-dashboard.yaml;
    key = "dashboard/session_secret";
    owner = "hermes";
    mode = "0400";
  };

  sops.templates."hermes-dashboard.env" = {
    owner = "hermes";
    mode = "0400";
    content = ''
      HERMES_DASHBOARD_BASIC_AUTH_USERNAME=chin39
      HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=${config.sops.placeholder."hermes-dashboard-password"}
      HERMES_DASHBOARD_BASIC_AUTH_SECRET=${config.sops.placeholder."hermes-dashboard-session-secret"}
    '';
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
      enable = true;
      backend = "docker";
      image = "ubuntu:24.04";
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
      extraOptions = [
        "--env"
        "HTTP_PROXY=http://192.168.0.240:10809"
        "--env"
        "HTTPS_PROXY=http://192.168.0.240:10809"
        "--env"
        "NO_PROXY=192.168.0.0/24,127.0.0.1,localhost"
        "--env"
        "TELEGRAM_PROXY=http://192.168.0.240:10809"

        # Load the app-server model bridge in Hermes' sealed Python, and put
        # the host-provided bubblewrap on the container PATH so Codex can use
        # its normal Linux sandbox without the bundled-fallback warning.
        "--env"
        "PYTHONPATH=${codexAppServerBridge}/${pkgs.python312.sitePackages}"
        "--env"
        "PATH=${pkgs.bubblewrap}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${codexPackage}/bin:${claudePackage}/bin"
      ];
    };

    environmentFiles = [
      config.sops.secrets."hermes-env".path
      config.sops.templates."hermes-dashboard.env".path
    ];

    settings = {
      # Primary chat model: Luna via Codex app-server and the Codex CLI's
      # ChatGPT subscription login. xhigh is configured under agent below.
      #
      # Empty base_url/api_key values are deliberate. Hermes reconciles these
      # managed settings into its stateful config.yaml with an additive merge:
      # it overwrites keys we set but does not prune dropped keys. Explicitly
      # clearing both removes the previous OpenCode Go endpoint and credential
      # reference so openai-codex can resolve the Codex CLI OAuth session.
      model = {
        default = codexLuna;
        provider = "openai-codex";
        openai_runtime = "codex_app_server";
        base_url = "";
        api_key = "";
      };

      # Default Codex reasoning level, forwarded per turn by the bridge.
      # Adjust live per session with `/reasoning <level>`.
      agent.reasoning_effort = "xhigh";

      # Subagent delegation — children run on Luna via the Codex OAuth
      # responses route (delegate_tool.py detects provider openai-codex; no
      # app-server binary involved). They inherit fallback_providers, so a
      # subscription outage drops them to the native DeepSeek chain.
      #
      # Tuning (schema defaults live in hermes_cli/config.py:1388):
      #   max_concurrent_children 4 — parallel children per batch (def 3).
      #   max_spawn_depth 2 — depth-1 children may spawn their own workers
      #     (def 1 = flat; clamped to [1,3]).
      #   child_timeout_seconds 900 — roomier per-child cap (def 600).
      delegation = (codexTarget codexLuna) // {
        max_concurrent_children = 4;
        max_spawn_depth = 2;
        child_timeout_seconds = 900;
      };

      # Auxiliary side-task models — subscription-first: text chores on Luna,
      # compression on Terra, each carrying a native-DeepSeek fallback_chain
      # so a Codex outage degrades to DeepSeek instead of failing.
      #
      # Chain trigger coverage (auxiliary_client.py:6925 should_fallback /
      # is_capacity_error): payment 402s, rate-limit 429s, connection and
      # timeout errors, allow-list 400s ("model incompatible with route"),
      # invalid responses — plus OAuth credentials that can't build a client
      # at all (_try_configured_fallback_for_unavailable_client). The one
      # exemption upstream enforces for explicit providers is an in-flight
      # 401: after any credential refresh fails the call aborts WITHOUT
      # walking the chain, and keeps aborting while the cached token still
      # builds a client. Recovery from a revoked login is manual: codex login.
      auxiliary = {
        title_generation = codexAuxTarget codexLuna;
        session_search = codexAuxTarget codexLuna;
        skills_hub = codexAuxTarget codexLuna;
        mcp = codexAuxTarget codexLuna;
        approval = codexAuxTarget codexLuna;
        web_extract = codexAuxTarget codexLuna;
        triage_specifier = codexAuxTarget codexLuna;
        curator = codexAuxTarget codexLuna;

        # Video understanding. Images rarely reach this role: with Luna as
        # main model, the native fast path (vision_tools.py:749) feeds them
        # straight into the Codex turn as input_image — subscription-billed.
        # Video has no Codex route, so it stays on the Go plan's kimi.
        vision = goTarget kimiVision;

        # Compression — upstream has dedicated Codex handling (272K cap,
        # codex_gpt55_autoraise); DeepSeek chain backstops it like the rest.
        compression = codexAuxTarget codexTerra;
      };

      compression = {
        enabled = true;
        threshold = 0.50;
        target_ratio = 0.20;
        protect_last_n = 20;
      };

      # Quick model switches. Luna/Terra/Sol use ChatGPT subscription auth;
      # DeepSeek aliases use its native API, while `pro` retains the previous
      # OpenCode Go-plan shortcut.
      model_aliases = {
        luna = codexTarget codexLuna;
        terra = codexTarget codexTerra;
        sol = codexTarget codexSol;

        # Native DeepSeek routes remain available even while the main model
        # uses the ChatGPT subscription-backed Codex runtime.
        deepseek = deepseekApiTarget deepseekPro;
        deepseek-flash = deepseekApiTarget deepseekFlash;

        # Existing Go-plan shortcut retained for compatibility.
        pro = goTarget deepseekPro;
      };

      # Named custom providers exposed to the `/model` picker. Only the Go
      # gateway remains — the local llama provider was removed along with
      # the rest of the local-llama wiring.
      custom_providers = [
        # opencode Zen "Go" plan — discover_models hits /v1/models on the
        # gateway and enumerates every Go-plan model into the /model
        # picker. Switch syntax: /model custom:opencode-go:<model-name>
        # (e.g. glm-5.2, qwen3.7-max, kimi-k2.7-code, minimax-m3).
        #
        # key_env (NOT api_key) is mandatory here: the discovery path
        # (model_switch.py: fetch_api_models) reads the entry's api_key
        # verbatim and does NOT interpolate a "${VAR}" — a literal
        # "${OPENCODE_API_KEY}" would be sent as the Bearer and 401, so the
        # picker shows zero models. key_env defers to a live
        # os.environ.get("OPENCODE_API_KEY") at /model time instead. (The
        # main chat path — model/auxiliary/fallback above — does expand
        # "${VAR}", which is why those keep the ${OPENCODE_API_KEY} form.)
        {
          name = "opencode-go";
          base_url = opencodeGoEndpoint;
          key_env = "OPENCODE_API_KEY";
          discover_models = true;
        }
      ];

      # Fallback chain for Hermes' own agent loop — walked on 5xx, timeout,
      # rate-limit, auth, or connection errors. Codex app-server owns its own
      # execution loop and does not consume this chain; switch manually to
      # `/model deepseek` if the ChatGPT-backed Codex route is unavailable.
      # References: hermes_cli/fallback_cmd.py, gateway/run.py:712.
      # This chain ALSO governs delegation subagents: delegate_tool.py
      # inherits the parent's _fallback_chain into spawned children
      # (see tools/delegate_tool.py:1078 / :1113).
      #
      # It uses the NATIVE DeepSeek API (deepseekApiTarget: provider
      # "deepseek" → api.deepseek.com + DEEPSEEK_API_KEY), not the Go gateway,
      # so DeepSeek Pro → flash remains an independent backstop for default-
      # runtime sessions and delegated work.
      fallback_providers = [
        (deepseekApiTarget deepseekPro)
        (deepseekApiTarget deepseekFlash)
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

  # Hermes no longer depends on llama-loader-shim: active roles now use Codex,
  # the Go gateway, or native DeepSeek. The shim service itself still exists
  # in services/llama-loader-shim.nix and can be disabled separately.

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

  # The upstream OCI image's HERMES_DASHBOARD=1 switch relies on s6, while
  # this module intentionally runs a plain Ubuntu container. Start the web UI
  # as a separate host service attached to the already-running container.
  systemd.services.hermes-dashboard = {
    description = "Hermes Agent Dashboard";
    wantedBy = [ "multi-user.target" ];
    after = [
      "docker.service"
      "hermes-agent.service"
    ];
    requires = [
      "docker.service"
      "hermes-agent.service"
    ];
    partOf = [ "hermes-agent.service" ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;

      ExecStartPre = [
        # Succeeds only once the container runs and the entrypoint has
        # created the hermes user — no first-boot race with useradd.
        (pkgs.writeShellScript "wait-for-hermes-container" ''
          for _ in $(${pkgs.coreutils}/bin/seq 1 ${toString dashboardWaitSeconds}); do
            if ${pkgs.docker}/bin/docker exec --user hermes hermes-agent true 2>/dev/null; then
              exit 0
            fi
            ${pkgs.coreutils}/bin/sleep 1
          done
          echo "hermes-dashboard: container did not become ready" >&2
          exit 1
        '')
        "-${dashboardCmd} --stop"
      ];
      ExecStart = "${dashboardCmd} --host 192.168.0.240 --port ${toString dashboardPort} --no-open --skip-build";
      ExecStop = "-${dashboardCmd} --stop";
    };
  };

  # LAN access to the dashboard.
  networking.firewall.allowedTCPPorts = [ dashboardPort ];
}
