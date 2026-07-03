{
  config,
  pkgs,
  inputs,
  ...
}:
let
  # DeepSeek tiers used in this config.
  deepseekPro = "deepseek-v4-pro"; # strongest — fallback + manual /model pro escalation
  deepseekFlash = "deepseek-v4-flash"; # mid — primary chat model + auxiliary chores

  # Vision-capable model for the auxiliary "vision" role. Both DeepSeek v4
  # tiers are text-only (confirmed against models.dev: modalities.input =
  # ["text"], no "attachment") — flash cannot see images. kimi-k2.6 (the
  # non "-code" Kimi K2 slug, confirmed present on this account's opencode
  # Zen "Go" plan) reports attachment:true with image+video input.
  kimiVision = "kimi-k2.6";

  # ── opencode Zen "Go" plan gateway ──────────────────────────────
  # OpenAI-compatible multi-model endpoint. Hermes' DeepSeek tiers now
  # bill against this Go plan instead of api.deepseek.com. provider
  # "custom" + explicit base_url/api_key is hermes' generic
  # OpenAI-compatible shape — the form every target in this file now
  # uses, replacing the built-in "deepseek" named provider, which
  # hardcoded api.deepseek.com + DEEPSEEK_API_KEY. The same key backs
  # the switchable `opencode-go` custom_provider below, which exposes
  # every Go-plan model (glm/qwen/kimi/minimax/…) to the /model picker.
  opencodeGoEndpoint = "https://opencode.ai/zen/go/v1";

  goBase = {
    provider = "custom";
    base_url = opencodeGoEndpoint;
    api_key = "\${OPENCODE_API_KEY}";
  };

  # A specific Go-plan model reached through the Go gateway.
  goTarget = model: goBase // { inherit model; };

  # Shared target for the flash tier (deepseek-v4-flash via the Go
  # gateway). Used by every text-only auxiliary role and — since the
  # local llama was retired — by delegation and the fallback's last
  # entry too.
  flashAuxTarget = goTarget deepseekFlash;

  # Vision-capable target for the auxiliary "vision" role only — flash
  # can't see images, so this role needs its own target (see kimiVision
  # above).
  visionAuxTarget = goTarget kimiVision;

  # ── Native DeepSeek API (fallback only) ─────────────────────────
  # The opencode Go plan that backs the primary/delegation/auxiliary
  # roles above went down, and the fallback chain previously ran on that
  # SAME gateway — so a Go-plan outage failed the whole chain with no
  # backstop. Point the fallback at DeepSeek's native API instead: a
  # different provider and a different credential (DEEPSEEK_API_KEY),
  # independent of the Go plan, so a Go outage now falls back cleanly.
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
      ];
    };

    environmentFiles = [
      config.sops.secrets."hermes-env".path
    ];

    settings = {
      # Primary chat model: deepseek-v4-flash — the mid tier, carrying
      # main conversations and orchestration. It now runs through the
      # opencode Zen "Go" gateway (goBase: provider "custom" + base_url
      # opencode.ai/zen/go/v1 + OPENCODE_API_KEY) instead of the built-in
      # "deepseek" named provider that hit api.deepseek.com directly.
      #
      # base_url/api_key are pinned explicitly ON PURPOSE. Hermes
      # reconciles these managed settings into the stateful
      # ~/.hermes/config.yaml with an additive deep-merge (hermes_cli/
      # config.py: _deep_merge / get_missing_config_fields): it OVERWRITES
      # keys we set but NEVER prunes keys we drop. Omitting base_url/api_key
      # would leave the previous endpoint behind as an orphan, so the
      # explicit Go-gateway values give the merge something to overwrite
      # on rebuild.
      #
      # The orchestrator runs on this model and hands simpler sub-steps
      # down to subagents via `delegation` below. When flash errors out
      # (5xx/timeout/rate-limit), fallback_providers escalates to DeepSeek
      # Pro, then retries flash — all via the Go gateway (the local llama
      # backstop was retired; see fallback_providers).
      model = goBase // {
        default = deepseekFlash;
      };

      # Subagent delegation — delegate_task spawns child agents on
      # deepseek-v4-flash via the Go gateway (formerly the local llama.cpp
      # via the loader-shim, retired when the Windows box went away).
      # delegate_tool.py uses delegation.base_url verbatim when set;
      # `model` must be explicit (goTarget supplies it), or an empty value
      # would inherit the parent's name unresolved.
      #
      # Tuning merged onto the Go flash target (schema defaults live in
      # hermes_cli/config.py:1388 "delegation"):
      #   max_concurrent_children 4 — parallel children per batch (def 3).
      #   max_spawn_depth 2 — let depth-1 children spawn their OWN workers
      #     for nested orchestration (def 1 = flat, leaf children only;
      #     clamped to [1,3]). Kept at 2, not 3 to cap how many concurrent
      #     Go-plan calls a deep tree can fan out into.
      #   child_timeout_seconds 900 — roomier per-child wall-clock cap
      #     (def 600) for large delegated tasks.
      delegation = (goTarget deepseekFlash) // {
        max_concurrent_children = 4;
        max_spawn_depth = 2;
        child_timeout_seconds = 900;
      };

      # Auxiliary side-task models. Every text-only role runs on
      # deepseek-v4-flash via the Go gateway (flashAuxTarget).
      # title_generation, session_search, skills_hub and mcp were
      # previously pinned to the local llama, but that timed out whenever
      # the Windows llama-server (192.168.0.101:8087) was down ("Auxiliary
      # title generation failed: Request timed out"); routing them through
      # the Go plan removes that dependency. NO role uses Pro — the
      # upstream schema comments uniformly recommend cheap/fast models
      # here, and the explicit flash pins keep these chores off Pro even
      # if the primary tier is raised.
      #
      # vision is the one role that isn't text-only, so it can't share
      # flashAuxTarget — deepseek-v4-flash is text-only (no "attachment"
      # in its models.dev entry) and silently can't see images. It's
      # pinned to visionAuxTarget (kimi-k2.6, image+video capable) instead.
      #
      # Note: auxiliary clients (agent/auxiliary_client.py) do NOT walk the
      # top-level fallback_providers chain — they have their own
      # credential/payment fallback machinery — so an aux call still fails
      # if the Go gateway itself is unreachable; these are deliberately
      # non-critical chores.
      auxiliary = {
        # Formerly local-pinned, now on the Go flash tier.
        title_generation = flashAuxTarget;
        session_search = flashAuxTarget;
        skills_hub = flashAuxTarget;
        mcp = flashAuxTarget;

        # Already flash: web summarisation, spec expansion, danger
        # classification, skill-curation review.
        approval = flashAuxTarget;
        web_extract = flashAuxTarget;
        triage_specifier = flashAuxTarget;
        curator = flashAuxTarget;

        # Image understanding — needs a vision-capable model, not flash.
        vision = visionAuxTarget;

        # Compression: same flash target plus the existing 30s timeout
        # override carried forward from the prior config (the per-role
        # default is 120s; 30s keeps compression latency tight).
        compression = flashAuxTarget // {
          timeout = 30;
        };
      };

      compression = {
        enabled = true;
        threshold = 0.50;
        target_ratio = 0.20;
        protect_last_n = 20;
      };

      # Quick-switch alias `/model pro` — manually escalate from the flash
      # primary up to the stronger DeepSeek Pro tier for a hard session.
      model_aliases = {
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

      # Fallback chain — walked when the primary errors (5xx, timeout,
      # rate-limit, auth, connection refused). Hermes' app-level retry
      # loop tries each entry in order before surfacing failure.
      # References: hermes_cli/fallback_cmd.py, gateway/run.py:712.
      # This chain ALSO governs delegation subagents: delegate_tool.py
      # inherits the parent's _fallback_chain into spawned children
      # (see tools/delegate_tool.py:1078 / :1113).
      #
      # The fallback now runs on the NATIVE DeepSeek API (deepseekApiTarget:
      # provider "deepseek" → api.deepseek.com + DEEPSEEK_API_KEY), NOT the
      # opencode Go gateway the primary uses. This is deliberate: the Go plan
      # is the thing that fails (it went down), so a same-gateway fallback was
      # useless. Routing the fallback through a separate provider + credential
      # gives the primary a real backstop when the Go plan is unavailable.
      # DeepSeek Pro (stronger tier) → flash retry, mirroring the previous
      # chain's tiers on the native slugs. The primary, delegation, auxiliary
      # and model_aliases stay on the Go gateway untouched.
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

  # (hermes no longer depends on the llama-loader-shim: every model role
  # now runs on the Go gateway, so the previous after/wants ordering on
  # llama-loader-shim.service was dropped. The shim service itself still
  # exists in services/llama-loader-shim.nix — disable it there if the
  # local llama is gone for good.)

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
