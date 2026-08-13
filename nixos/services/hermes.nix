{
  config,
  lib,
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
  # Keep the model IDs bare: openai-codex resolves them through its Codex
  # catalog and does not use the OpenCode `openai/` naming convention.
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
  # Multi-model endpoint behind the `/model pro` and `/model flash` shortcuts
  # and the switchable `opencode-go` provider. The first-class provider keeps
  # Hermes' per-model Go routing and reasoning request shaping active.
  opencodeGoEndpoint = "https://opencode.ai/zen/go/v1";

  # OPENCODE_GO_API_KEY, not OPENCODE_API_KEY: hermes' built-in opencode-go
  # provider only reads the former (hermes_cli/auth.py PROVIDER_REGISTRY), and
  # /model switches resolve credentials through that registry rather than
  # through the api_key written here. With the old name, every `/model pro`
  # died on "No usable credentials found for provider 'opencode-go'" even
  # though the chat path worked — it expands this ${VAR} itself.
  goBase = {
    provider = "opencode-go";
    base_url = opencodeGoEndpoint;
    api_key = "\${OPENCODE_GO_API_KEY}";
  };

  # A specific Go-plan model reached through the Go gateway.
  goTarget = model: goBase // { inherit model; };

  # ── Native DeepSeek API (fallback + manual aliases) ──────────────
  # Keep a route independent of the OpenCode Go plan and its credential.
  # This backs the fallback chain on Hermes' default runtime plus the manual
  # `/model deepseek` and `/model deepseek-flash` switches.
  #
  # provider = "deepseek" is Hermes' built-in native provider. It activates
  # DeepSeekProfile for the direct API's thinking controls; Go traffic uses
  # the separate opencode-go profile because that relay has its own request
  # shaping and per-model protocol routing.
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

  # Summarization is extraction, not reasoning — high is enough. The effort
  # is shared with the chain: this rev only honours per-entry timeout and
  # api_key (auxiliary_client.py:4713/5419). No timeout key: compression
  # timeouts are already floored at 300s (auxiliary_client.py:7737).
  compressionAux = (codexTarget codexTerra) // {
    reasoning_effort = "high";
    # Per-entry 300s — otherwise a fallback runs on whatever is left of the
    # primary's deadline (#62452).
    fallback_chain = [
      ((deepseekApiTarget deepseekPro) // { timeout = 300; })
      ((deepseekApiTarget deepseekFlash) // { timeout = 300; })
    ];
  };

  # Shared by the default config and every named profile; profiles are
  # standalone clones, so a key left out here diverges silently.
  compressionPolicy = {
    enabled = true;

    # Reaches the main model raised, not as written: context_compressor
    # floors sub-512K windows at 0.75, and the Codex gpt-5.6 autoraise
    # takes it to 0.85. Only >=512K fallback models see 0.50.
    threshold = 0.50;

    target_ratio = 0.20;
    protect_last_n = 20;

    # Bulky tool output can fill the whole tail budget; keep the last 3
    # real user turns verbatim.
    min_tail_user_messages = 3;

    # Default false swaps the middle window for a placeholder when the
    # summary call fails, losing history. Freeze instead; /compress resumes.
    abort_on_summary_failure = true;

    # No-LLM prune of stale large tool results, which the 0.85 trigger
    # otherwise re-sends every turn until ~231K. min_reclaim keeps the
    # prompt-cache breaks episodic rather than per-turn.
    proactive_prune_tokens = 96000;
    proactive_prune_min_result_chars = 12000;
    proactive_prune_min_reclaim_tokens = 8192;

    # OpenAI server-side compaction on the Responses API. Gated in
    # native_compaction.py to the gpt-5.6 family on api.openai.com or the
    # Codex backend; other models stay on the local summarizer, which also
    # remains the fallback owner.
    codex_responses_native = true;

    # Clamped at request time to (local trigger - 8192), so the server
    # compacts first without assuming a fixed gpt-5.6 window.
    codex_responses_compact_threshold = 200000;

    # OpenAI evicts cached prefixes within an hour, so a resume after this
    # gap never has a warm cache — compact the stale history up front.
    idle_compact_after_seconds = 3600;
  };

  # Same codex/claude builds home-manager installs — nix-provided so they
  # survive container recreation (replacing the npm-global copies).
  codexPackage = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  claudePackage = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # ── Browser automation runtime ──────────────────────────────────
  # The Ubuntu container only bind-mounts /nix/store; installing a browser
  # package on the host does not make Ubuntu's dynamic loader discover its
  # libraries. Point browser clients at Nix-patched executables instead, whose
  # complete runtime closure is encoded in their RPATH/wrappers.
  browserFonts = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];
  browserFontConfig = pkgs.makeFontsConf {
    fontDirectories = browserFonts;
  };

  # Generic Chromium consumers (Hermes agent-browser, Puppeteer, Selenium,
  # Lighthouse, etc.) share this executable. The flags are scoped to this
  # wrapper and are required for an unprivileged browser inside Docker.
  hermesChromium = pkgs.chromium.override {
    commandLineArgs = "--no-sandbox --disable-dev-shm-usage";
  };
  hermesChromiumExecutable = lib.getExe hermesChromium;

  # Playwright browser revisions are tied to the Playwright driver version.
  # Keep its Nix-patched Chromium + headless-shell + ffmpeg set separate from
  # pkgs.chromium instead of forcing Playwright onto an arbitrary system build.
  playwrightChromiumBrowsers = pkgs.playwright-driver.browsers.override {
    withFirefox = false;
    withWebkit = false;
    fontconfig_file = browserFontConfig;
  };

  # Both the Python CLI and in-process API spawn the Nix-pinned Node driver
  # through get_driver_env(). Inject its revision-coupled browser cache at that
  # boundary so unrelated Playwright consumers keep their own cache/revision.
  pythonPlaywright = pkgs.python312Packages.playwright.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      substituteInPlace playwright/_impl/_driver.py \
        --replace-fail \
          '    env = os.environ.copy()' \
          '    env = os.environ.copy()
          env["PLAYWRIGHT_BROWSERS_PATH"] = "${playwrightChromiumBrowsers}"
          env["PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD"] = "1"'
    '';
  });
  pythonPlaywrightPath = lib.makeSearchPath pkgs.python312.sitePackages [
    pythonPlaywright
    pkgs.python312Packages.greenlet
    pkgs.python312Packages.pyee
  ];

  # PATH-based discovery pins agent-browser itself (avoiding its npx fallback)
  # and covers chromedriver/Selenium plus the Playwright CLI. Python Playwright
  # is also added to PYTHONPATH below because Hermes' Google Meet plugin imports
  # it in-process from the sealed Python runtime.
  browserAutomationPath = lib.makeBinPath [
    pkgs.agent-browser
    hermesChromium
    pkgs.chromedriver
    pythonPlaywright
  ];

  # The upstream NixOS module currently renders settings only to the default
  # profile's config.yaml. Named Hermes profiles each have an independent
  # config.yaml under profiles/<name>/, so merge the Nix-owned leaves into
  # those existing files with the same helper upstream uses for the default
  # profile. User-added settings remain intact.
  #
  # Only leaves that actually differ from the upstream default are set here:
  # `agent.tool_use_enforcement` is already "auto" upstream
  # (hermes_cli/config.py), so pinning it would add nine copies of a no-op.
  profileConfig = model: reasoningEffort: toolsets: {
    model = (codexTarget model) // {
      openai_runtime = "auto";
      api_mode = "codex_responses";
    };
    agent.reasoning_effort = reasoningEffort;

    # Profile config.yaml files are standalone clones, not overlays on the
    # default profile, so the policy and the aux summarizer must be
    # repeated here or Profile sessions silently diverge.
    compression = compressionPolicy;
    auxiliary.compression = compressionAux;

    # `platform_toolsets.cli` is what direct CLI sessions and Kanban workers
    # resolve. Every entry is a real 0.19.0 toolset; `gateway` is a process-
    # level dispatcher, not an agent toolset in this Hermes release.
    platform_toolsets.cli = toolsets;
  };

  # Profile-specific model/effort/toolsets, descriptions, and SOULs live in
  # a separate declarative file. Generic Hermes/Kanban/runtime settings remain
  # in this service module.
  specialistProfileData = import ./hermes-profile-definitions.nix {
    inherit
      profileConfig
      codexLuna
      codexTerra
      codexSol
      ;
  };
  specialistProfiles = specialistProfileData.specialistProfiles;
  specialistProfileDescriptions = specialistProfileData.specialistProfileDescriptions;
  specialistSouls = specialistProfileData.specialistSouls;

  # Both asset files are JSON on purpose: configMergeScript reads its first
  # argument with json.load and only its *target* is YAML. Writing the
  # description side as .json keeps that contract visible -- an earlier
  # revision used lib.generators.toYAML, which happens to emit JSON today and
  # would have broken silently against a real YAML emitter.
  specialistProfileAssets = lib.mapAttrs (name: settings: {
    settingsFile = pkgs.writeText "hermes-profile-${name}.json" (builtins.toJSON settings);
    descriptionFile = pkgs.writeText "hermes-profile-description-${name}.json" (
      builtins.toJSON {
        description = specialistProfileDescriptions.${name};
        description_auto = false;
      }
    );
    soulFile = pkgs.writeText "hermes-soul-${name}.md" specialistSouls.${name};
  }) specialistProfiles;

  hermesConfigMerge = pkgs.callPackage (inputs.hermes-agent + "/nix/configMergeScript.nix") { };

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
      #   - slack.com — directly reachable; routing it through the proxy
      #     caused duplicate posts (proxy drops the response after Slack
      #     accepts chat.postMessage → slack_sdk's default connection-error
      #     retry re-sends the same message)
      extraOptions = [
        "--env"
        "HTTP_PROXY=http://192.168.0.240:10809"
        "--env"
        "HTTPS_PROXY=http://192.168.0.240:10809"
        "--env"
        "NO_PROXY=192.168.0.0/24,127.0.0.1,localhost,slack.com,.slack.com"
        "--env"
        "TELEGRAM_PROXY=http://192.168.0.240:10809"

        # Keep these lowercase copies. apt honours only the lowercase spelling
        # (verified: an unreachable http_proxy fails apt, an unreachable
        # HTTP_PROXY does not), while curl accepts either. With the uppercase
        # names alone, the container's first-boot provisioning split across two
        # routes -- curl fetched the NodeSource key through the proxy while apt
        # installed nodejs over a direct connection, which is unreliable from
        # here. That half-finished provisioning is what left the service in a
        # restart loop on 2026-07-25.
        "--env"
        "http_proxy=http://192.168.0.240:10809"
        "--env"
        "https_proxy=http://192.168.0.240:10809"
        "--env"
        "no_proxy=192.168.0.0/24,127.0.0.1,localhost,slack.com,.slack.com"

        # Nix-managed browser automation. Export only version-agnostic browser
        # discovery globally. Playwright's revision-coupled cache is scoped to
        # the matching Python driver above.
        "--env"
        "AGENT_BROWSER_EXECUTABLE_PATH=${hermesChromiumExecutable}"
        "--env"
        "AGENT_BROWSER_ARGS=--no-sandbox,--disable-dev-shm-usage"
        "--env"
        "CHROME_BIN=${hermesChromiumExecutable}"
        "--env"
        "CHROME_PATH=${hermesChromiumExecutable}"
        "--env"
        "CHROMIUM_BIN=${hermesChromiumExecutable}"
        "--env"
        "CHROMIUM_PATH=${hermesChromiumExecutable}"
        "--env"
        "PUPPETEER_EXECUTABLE_PATH=${hermesChromiumExecutable}"
        "--env"
        "PUPPETEER_SKIP_DOWNLOAD=true"
        "--env"
        "PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true"
        "--env"
        "FONTCONFIG_FILE=${browserFontConfig}"

        # Expose the Nix Python Playwright package to Hermes' sealed Python;
        # its child driver gets the matching browser cache from the package
        # override above. Keep host-provided bubblewrap on PATH for an
        # explicit codex app-server switch.
        "--env"
        "PYTHONPATH=${pythonPlaywrightPath}"
        "--env"
        "PATH=${pkgs.bubblewrap}/bin:${browserAutomationPath}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${codexPackage}/bin:${claudePackage}/bin"
      ];
    };

    environmentFiles = [
      config.sops.secrets."hermes-env".path
      config.sops.templates."hermes-dashboard.env".path
    ];

    settings = {
      # Primary chat model: Terra via Hermes' native agent loop and the Codex
      # Responses OAuth route backed by the Codex CLI's ChatGPT login.
      #
      # Empty base_url/api_key values are deliberate. Hermes reconciles these
      # managed settings into its stateful config.yaml with an additive merge:
      # it overwrites keys we set but does not prune dropped keys. Explicitly
      # clearing both removes the previous OpenCode Go endpoint and credential
      # reference so openai-codex can resolve the Codex CLI OAuth session.
      model = {
        default = codexTerra;
        provider = "openai-codex";
        openai_runtime = "auto";

        # Overwrites the stale `codex_app_server` the 2026-07-19 app-server
        # experiment left behind — the additive merge cannot delete keys.
        # Inert for openai-codex (all three resolution paths hard-set
        # codex_responses: runtime_provider.py:465/1533/1958), but a later
        # provider switch would honour the persisted value verbatim.
        api_mode = "codex_responses";

        base_url = "";
        api_key = "";
      };

      # Default reasoning level for the Hermes-managed Codex Responses client.
      # Adjust live per session with `/reasoning <level>`.
      #
      # tool_use_enforcement is deliberately not pinned: "auto" is already the
      # upstream default and it has never been set in the stateful config, so
      # declaring it would only add a leaf that always matches the default.
      agent = {
        reasoning_effort = "high";

        # Main fallback activation resolves effort by model ID, not by the
        # fallback entry. These overrides therefore also apply to manual
        # switches to the same Terra and DeepSeek Pro/Flash model IDs.
        reasoning_overrides = {
          ${codexTerra} = "xhigh";
          ${deepseekFlash} = "max";
          ${deepseekPro} = "max";
        };
      };

      # Subagent delegation — children run on Luna via the Codex OAuth
      # responses route (delegate_tool.py detects provider openai-codex; no
      # app-server binary involved). They inherit fallback_providers, so a
      # subscription outage walks the same Terra → Go Pro → native Pro
      # chain as the parent, skipping an entry identical to the failed backend.
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
        triage_specifier = (codexAuxTarget codexTerra) // {
          reasoning_effort = "high";
          timeout = 180;
        };
        kanban_decomposer = (codexAuxTarget codexTerra) // {
          reasoning_effort = "xhigh";
          timeout = 300;
        };
        profile_describer = (codexAuxTarget codexLuna) // {
          reasoning_effort = "high";
          timeout = 180;
        };
        goal_judge = (codexAuxTarget codexTerra) // {
          reasoning_effort = "high";
        };
        curator = codexAuxTarget codexLuna;

        # Video understanding. Images rarely reach this role: with Luna as
        # main model, the native fast path (vision_tools.py:749) feeds them
        # straight into the Codex turn as input_image — subscription-billed.
        # Video has no Codex route, so it stays on the Go plan's kimi.
        vision = goTarget kimiVision;

        # Compression — upstream has dedicated Codex handling (272K cap,
        # codex_gpt55_autoraise); DeepSeek chain backstops it like the rest.
        compression = compressionAux;
      };

      compression = compressionPolicy;

      # Quick model switches. Luna/Terra/Sol use ChatGPT subscription auth;
      # `deepseek`/`deepseek-flash` use the native API, `pro`/`flash` the Go
      # plan.
      #
      # For the Go DeepSeek models the alias is the ONLY reliable route.
      # model_switch.resolve_alias() also reverse-matches a typed model id
      # against every alias' model, then overwrites base_url with that alias'
      # (model_switch.py:976 + :1772) — so `/model deepseek-v4-flash
      # --provider custom:opencode-go`, and picking it from the /model picker,
      # both land on api.deepseek.com. Alias-name lookup wins before that.
      model_aliases = {
        luna = codexTarget codexLuna;
        terra = codexTarget codexTerra;
        sol = codexTarget codexSol;

        # Native DeepSeek routes remain available even while the main model
        # uses the ChatGPT subscription-backed Codex runtime.
        deepseek = deepseekApiTarget deepseekPro;
        deepseek-flash = deepseekApiTarget deepseekFlash;

        # Go-plan DeepSeek tiers.
        pro = goTarget deepseekPro;
        flash = goTarget deepseekFlash;
      };

      # Named custom providers exposed to the `/model` picker. Only the Go
      # gateway remains — the local llama provider was removed along with
      # the rest of the local-llama wiring.
      custom_providers = [
        # opencode Zen "Go" plan — discover_models hits /v1/models on the
        # gateway and enumerates every Go-plan model into the /model picker.
        # Switch syntax: /model <model-name> --provider opencode-go
        # (e.g. glm-5.2, qwen3.7-max, kimi-k2.7-code, minimax-m3), or the
        # `pro`/`flash` aliases for DeepSeek. There is no
        # `custom:<name>:<model>` form — that string is taken as a model id
        # and rejected by the current provider.
        #
        # key_env (NOT api_key) is mandatory here: the discovery path
        # (model_switch.py: fetch_api_models) reads the entry's api_key
        # verbatim and does NOT interpolate a "${VAR}" — a literal
        # "${OPENCODE_GO_API_KEY}" would be sent as the Bearer and 401, so the
        # picker shows zero models. key_env defers to a live
        # os.environ.get("OPENCODE_GO_API_KEY") at /model time instead. (The
        # main chat path — model/auxiliary/fallback above — does expand
        # "${VAR}", which is why those keep the ${OPENCODE_GO_API_KEY} form.)
        #
        # Same var as the built-in provider so both routes share one secret;
        # with it set, the picker collapses this entry into the built-in
        # "OpenCode Go" row, which derives api_mode per model — minimax/qwen
        # need anthropic_messages and 404 on the generic custom: route.
        {
          name = "opencode-go";
          base_url = opencodeGoEndpoint;
          key_env = "OPENCODE_GO_API_KEY";
          discover_models = true;
        }
      ];

      # Fallback chain for Hermes' agent loop — now active for the primary
      # Codex Responses route and walked on 5xx, timeout, rate-limit, auth, or
      # connection errors.
      # References: hermes_cli/fallback_cmd.py, gateway/run.py:712.
      # This chain ALSO governs delegation subagents: delegate_tool.py
      # inherits the parent's _fallback_chain into spawned children
      # (see tools/delegate_tool.py:1078 / :1113).
      #
      # Order and credentials are deliberate: try Codex through Terra first,
      # then use the OpenCode Go-plan Pro route, then the independently
      # credentialled native DeepSeek Pro route. Hermes skips Terra when the
      # failed backend was already openai-codex/Terra.
      fallback_providers = [
        (codexTarget codexTerra)
        (goTarget deepseekPro)
        (deepseekApiTarget deepseekPro)
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

      kanban = {
        dispatch_in_gateway = true;
        dispatch_interval_seconds = 15;
        failure_limit = 2;
        auto_decompose = true;
        auto_decompose_per_tick = 3;
        orchestrator_profile = "orchestrator";
        default_assignee = "orchestrator";
        auto_subscribe_on_create = true;
        auto_promote_children = true;
        max_in_progress = 4;
        max_in_progress_per_profile = 2;
      };

      dashboard.kanban = {
        lane_by_profile = true;
        include_archived_by_default = false;
        render_markdown = true;
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

  # Upstream has no services.hermes-agent.profiles option yet. Keep Profile
  # model/effort/toolsets, descriptions, and SOULs declarative without
  # replacing the rest of each Profile's stateful config. Profiles are created
  # with the official `hermes profile create --clone` path first; a missing one
  # fails loudly instead of silently yielding a partial identity.
  #
  # This is a unit rather than a system.activationScripts entry on purpose.
  # `exit 1` inside an activation snippet aborts the *whole* activation, and
  # the snippets that carry no declared dependency (modprobe, stdio, udevd,
  # usrbinenv, var) are ordered after this one -- so one missing Hermes
  # directory would silently skip unrelated system setup and fail the switch.
  # As a unit the blast radius is Hermes: hermes-agent.service requires this
  # one, so Hermes refuses to start while the rest of the system activates
  # normally. `hermes profile create` writes under stateDir, so ordering after
  # the upstream setup unit is enough -- no activation-time hook needed.
  #
  # Note SOUL.md is Nix-owned from here on: edits made through the Hermes CLI
  # or TUI are overwritten on the next start of this unit.
  systemd.services.hermes-agent-profile-settings = {
    description = "Nix-managed Hermes Profile settings, descriptions, and SOULs";
    wantedBy = [ "multi-user.target" ];
    before = [ "hermes-agent.service" ];
    requiredBy = [ "hermes-agent.service" ];
    path = [ pkgs.coreutils ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      profiles_root=${config.services.hermes-agent.stateDir}/.hermes/profiles

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: assets: ''
          profile_dir="$profiles_root/${name}"
          if [ ! -d "$profile_dir" ]; then
            echo "hermes-agent: required Profile '${name}' is missing at $profile_dir" >&2
            echo "hermes-agent: create it with 'hermes profile create ${name} --clone --no-alias' first" >&2
            exit 1
          fi

          # Require the cloned config.yaml too. Merging into a missing file
          # would produce one holding *only* the Nix-owned leaves, which reads
          # like a working Profile while having lost every other setting.
          if [ ! -f "$profile_dir/config.yaml" ]; then
            echo "hermes-agent: Profile '${name}' has no config.yaml at $profile_dir" >&2
            echo "hermes-agent: recreate it with 'hermes profile create ${name} --clone --no-alias'" >&2
            exit 1
          fi

          ${hermesConfigMerge} ${assets.settingsFile} "$profile_dir/config.yaml"
          install -m 0660 ${assets.soulFile} "$profile_dir/SOUL.md"
          ${hermesConfigMerge} ${assets.descriptionFile} "$profile_dir/profile.yaml"
          chown ${config.services.hermes-agent.user}:${config.services.hermes-agent.group} "$profile_dir/config.yaml" "$profile_dir/SOUL.md" "$profile_dir/profile.yaml"
          chmod 0660 "$profile_dir/config.yaml"
          chmod 0660 "$profile_dir/SOUL.md"
          chmod 0644 "$profile_dir/profile.yaml"

          # Profile directories have drifted: some are 0755, some 0777. Pin
          # them to the setgid group-owned mode upstream uses for its own
          # stateDir subdirectories.
          chown ${config.services.hermes-agent.user}:${config.services.hermes-agent.group} "$profile_dir"
          chmod 2770 "$profile_dir"
        '') specialistProfileAssets
      )}
    '';
  };

  # Hermes no longer depends on llama-loader-shim: active roles now use Codex,
  # the Go gateway, or native DeepSeek. The shim service itself still exists
  # in services/llama-loader-shim.nix and can be disabled separately.

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
