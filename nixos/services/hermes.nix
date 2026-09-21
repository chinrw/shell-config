{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # Keep the Node test workaround inside Hermes's own nixpkgs scope.
  hermesPkgs =
    inputs.hermes-agent.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.extend
      (
        _final: prev: {
          nodejs-slim_26 = prev.nodejs-slim_26.overrideAttrs (old: {
            patches =
              (old.patches or [ ])
              ++ lib.optionals (old.version == "26.9.0") [
                # Remove once pinned nixpkgs includes nodejs/node#66104 and
                # Hermes builds successfully without this patch.
                ./patches/node-26.9.0-fs-cp-file-modes.patch
              ];
          });
        }
      );

  # Canonical V4.1 Flash ID for both DeepSeek and OpenCode Go.
  deepseekFlash = "deepseek-flash";

  qwenVision = "qwen3.8-flash";

  # GPT models reached through Codex CLI's ChatGPT subscription login.
  # Keep the model IDs bare: openai-codex resolves them through its Codex
  # catalog and does not use the OpenCode `openai/` naming convention.
  codexLuna = "gpt-5.6-luna";
  codexTerra = "gpt-5.6-terra";
  codexSol = "gpt-5.6-sol";
  codexAstra = "gpt-6-astra";

  # Explicit empty values clear endpoint credentials during additive config merge.
  codexTarget = model: {
    provider = "openai-codex";
    inherit model;
    base_url = "";
    api_key = "";
  };

  opencodeGoEndpoint = "https://opencode.ai/zen/go/v1";

  # The native Go provider requires OPENCODE_GO_API_KEY for model switches.
  goBase = {
    provider = "opencode-go";
    base_url = opencodeGoEndpoint;
    api_key = "\${OPENCODE_GO_API_KEY}";
  };

  goTarget = model: goBase // { inherit model; };

  # The explicit API host lets Hermes resolve DEEPSEEK_API_KEY independently of Go.
  deepseekApiTarget = model: {
    provider = "deepseek";
    base_url = "https://api.deepseek.com/v1";
    inherit model;
  };

  commandcodeEndpoint = "https://api.commandcode.ai/provider/v1";
  commandcodeFlash = "deepseek/deepseek-v4.1-flash";
  commandcodeProvider = {
    name = "CommandCode API";
    base_url = commandcodeEndpoint;
    key_env = "COMMAND_CODE_API";
    transport = "chat_completions";
    discover_models = true;
    models.${commandcodeFlash} = {
      context_length = 1000000;
      supports_vision = true;
    };
  };
  commandcodeFlashTarget = {
    # Select the configured key_env rather than the built-in COMMANDCODE_API_KEY.
    provider = "commandcode-api";
    base_url = commandcodeEndpoint;
    key_env = "COMMAND_CODE_API";
    model = commandcodeFlash;
  };

  # Auxiliary calls use their own fallback chain when Codex fails.
  codexAuxTarget =
    model:
    (codexTarget model)
    // {
      fallback_chain = [
        (deepseekApiTarget deepseekFlash)
      ];
    };

  summaryTimeoutSeconds = 300;

  # All summary routes need 1M context to avoid lowering the main compaction trigger.
  compressionAux = (goTarget deepseekFlash) // {
    reasoning_effort = "high";
    timeout = summaryTimeoutSeconds;
    # Each fallback needs its own timeout rather than the primary's remaining time.
    fallback_chain = [
      ((deepseekApiTarget deepseekFlash) // { timeout = summaryTimeoutSeconds; })
    ];
  };

  # LCM owns summary escalation; auxiliary retries must not bypass its chain.
  lcmSummaryRoutes = {
    primary = (goTarget deepseekFlash) // {
      reasoning_effort = "high";
      timeout = summaryTimeoutSeconds;
      fallback_chain = [ ];
    };
    fallbackModels = [
      "commandcode-api/${commandcodeFlash}"
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

    # Budget for serial leaf-summary and condensation calls.
    context_total_ceiling_seconds = 900;

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

    # Native Codex compaction runs before the local compression fallback.
    codex_responses_native = true;

    # Clamped at request time to (local trigger - 8192), so the server
    # compacts first without assuming a fixed gpt-5.6 window.
    codex_responses_compact_threshold = 200000;

    # OpenAI evicts cached prefixes within an hour, so a resume after this
    # gap never has a warm cache — compact the stale history up front.
    idle_compact_after_seconds = 3600;
  };

  sharedSettings = {
    agent.image_input_mode = "native";
    compression = compressionPolicy;
    auxiliary = {
      title_generation = codexAuxTarget codexLuna;
      session_search = codexAuxTarget codexLuna;
      skills_hub = codexAuxTarget codexLuna;
      mcp = codexAuxTarget codexLuna;
      approval = codexAuxTarget codexLuna;
      web_extract = codexAuxTarget codexLuna;
      curator = codexAuxTarget codexLuna;
      # Images go to the main model; video_analyze uses this auxiliary endpoint.
      vision = goTarget qwenVision;
      video.model = qwenVision;
    };
    providers.commandcode-api = commandcodeProvider;
    model_aliases = {
      luna = codexTarget codexLuna;
      terra = codexTarget codexTerra;
      sol = codexTarget codexSol;
      astra = codexTarget codexAstra;
      deepseek = deepseekApiTarget deepseekFlash;
      deepseek-flash = deepseekApiTarget deepseekFlash;
      flash = goTarget deepseekFlash;
      flash-cc = commandcodeFlashTarget;
    };
  };

  # Same codex/claude builds home-manager installs — nix-provided so they
  # survive container recreation (replacing the npm-global copies).
  codexPackage = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  claudePackage = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # ── Fonts ───────────────────────────────────────────────────────
  # FONTCONFIG_FILE below is process-wide, so this also covers ImageMagick,
  # matplotlib and anything else in the container that renders CJK text.
  browserFonts = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];
  browserFontConfig = pkgs.makeFontsConf {
    fontDirectories = browserFonts;
  };

  # Browsers run in browser-agent containers and are reached over CDP.

  # Decode share-link QR codes locally to avoid vision transcription errors.
  # Skill runners use python -E, so provide the zbarimg CLI.
  qrDecoder = pkgs.zbar.override {
    withXorg = false;
    enableVideo = false;
    imagemagickBig = pkgs.imagemagick;
  };

  # Named profiles are standalone configs; merge shared policy before role overrides.
  profileConfig =
    model: reasoningEffort: toolsets:
    lib.recursiveUpdate sharedSettings {
      model = {
        default = model;
        provider = "openai-codex";
        base_url = "";
        api_key = "";
        openai_runtime = "auto";
        api_mode = "codex_responses";
      };
      agent.reasoning_effort = reasoningEffort;

      auxiliary.compression = compressionAux;
      auxiliary.triage_specifier.fallback_chain = [ (deepseekApiTarget deepseekFlash) ];
      fallback_providers = [ (deepseekApiTarget deepseekFlash) ];

      # CLI sessions and Kanban workers use this toolset list.
      platform_toolsets.cli = toolsets;
    };

  # Everything hermes-lcm (container env, config leaves, plugin install)
  # lives in a separate declarative file, same pattern as the profile
  # definitions below; this module splices its three exports into place.
  hermesLcm = import ./hermes-lcm.nix {
    inherit
      pkgs
      lib
      inputs
      ;
    summaryModel = lcmSummaryRoutes.primary.model;
    summaryFallbackModels = lcmSummaryRoutes.fallbackModels;
    inherit summaryTimeoutSeconds;
    user = config.services.hermes-agent.user;
    group = config.services.hermes-agent.group;
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

  # configMergeScript reads JSON overrides and writes YAML targets.
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

  # Keep identical host/container paths for qB and skill interoperability.
  # Mount only media subtrees; rslave propagates host virtiofs remounts.
  mediaRoot = "/mnt/data";
  hostPathVolume = path: "${path}:${path}:rw,rslave";
  mediaVolumes = map hostPathVolume [
    "${mediaRoot}/harmony"
    "${mediaRoot}/Downloads"
    "${mediaRoot}/Video"
    "${mediaRoot}/baidu"
  ];

  # ── Dashboard ───────────────────────────────────────────────────
  dashboardPort = 9119;
  dashboardWaitSeconds = 30;
  dashboardCmd = "${pkgs.docker}/bin/docker exec --user hermes hermes-agent /data/current-package/bin/hermes dashboard";
in
{
  imports = [
    (import ./hermes-container-provisioning.nix {
      inherit lib;
      hermesInput = inputs.hermes-agent;
    })
  ];

  # SOPS decrypts credentials at activation; never embed their values in Nix.
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
    package = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      callPackage = hermesPkgs.callPackage;
    };
    addToSystemPackages = true;

    # The upstream CLI router runs Hermes as the service user inside this container.
    container = {
      enable = true;
      backend = "docker";
      image = "ubuntu:24.04";
      hostUsers = [ "chin39" ];

      # Host ACLs grant gid 985 access; setpriv --init-groups discards --group-add.
      extraVolumes = mediaVolumes ++ [
        "/var/lib/rclone-progress/view:/run/rclone-progress:ro"
      ];

      # docker create --env reaches provisioning, wrappers, and Python with -E.
      # List LAN hosts explicitly: Python proxy handling does not support CIDR.
      # Slack bypasses the proxy to avoid connection-loss retries duplicating posts.
      extraOptions = [
        "--env"
        "HTTP_PROXY=http://192.168.0.240:10809"
        "--env"
        "HTTPS_PROXY=http://192.168.0.240:10809"
        "--env"
        "NO_PROXY=192.168.0.0/24,192.168.0.101,127.0.0.1,localhost,slack.com,.slack.com"
        "--env"
        "TELEGRAM_PROXY=http://192.168.0.240:10809"
        "--env"
        "HERMES_TELEGRAM_HTTP_POOL_TIMEOUT=30"
        "--env"
        "HERMES_TELEGRAM_HTTP_CONNECT_TIMEOUT=30"

        # apt requires lowercase proxy variables.
        "--env"
        "http_proxy=http://192.168.0.240:10809"
        "--env"
        "https_proxy=http://192.168.0.240:10809"
        "--env"
        "no_proxy=192.168.0.0/24,192.168.0.101,127.0.0.1,localhost,slack.com,.slack.com"

        # Share CJK fonts across ImageMagick, matplotlib, and other renderers.
        "--env"
        "FONTCONFIG_FILE=${browserFontConfig}"

        # Inject FastEmbed dependencies; keep bubblewrap available for Codex app-server.
        "--env"
        "PYTHONPATH=${hermesLcm.pythonPath}"
        "--env"
        "PATH=${pkgs.bubblewrap}/bin:${qrDecoder}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${codexPackage}/bin:${claudePackage}/bin"
      ]
      # LCM summarizer/behaviour env — see hermes-lcm.nix for the rationale.
      ++ hermesLcm.containerEnvOptions;
    };

    environmentFiles = [
      config.sops.secrets."hermes-env".path
      config.sops.templates."hermes-dashboard.env".path
    ];

    settings = lib.recursiveUpdate sharedSettings {
      # Main-loop effort overrides follow model switches and delegation.
      # Auxiliary tasks carry their own reasoning effort.
      model = {
        default = codexLuna;
        provider = "openai-codex";
        openai_runtime = "auto";

        # Clear persisted app-server mode during additive config reconciliation.
        api_mode = "codex_responses";

        base_url = "";
        api_key = "";
      };

      # /reasoning can override the default for the current session.
      agent = {
        reasoning_effort = "high";

        # Model-level effort applies to both fallbacks and manual switches.
        reasoning_overrides = {
          ${codexLuna} = "xhigh";
          ${codexTerra} = "xhigh";
          ${deepseekFlash} = "max";
          ${commandcodeFlash} = "max";
        };
      };

      # Keep the Go context window independent of cached provider metadata.
      model_overrides = {
        opencode-go.deepseek-flash.context_window = 1000000;
      };

      # Unpinned delegates inherit the main fallback chain.
      delegation = (codexTarget codexLuna) // {
        max_concurrent_children = 4;
        max_spawn_depth = 2;
        child_timeout_seconds = 900;
      };

      # Curator auto-prune
      curator = {
        interval_hours = 24;
        stale_after_days = 14;
        archive_after_days = 60;
        archive_ttl_days = 90;
      };

      auxiliary = {
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
        compression = lcmSummaryRoutes.primary;
      };

      # hermes-lcm context engine for default-profile/gateway sessions —
      # scope, interplay with native compaction, and all rationale live in
      # hermes-lcm.nix. Specialist profiles keep the built-in compressor.
      inherit (hermesLcm.settings) context plugins;

      # Named custom providers exposed to the `/model` picker: the Go
      # gateway and the local llama.cpp router on the Windows box.
      custom_providers = [
        # Discovery reads key_env; it does not expand ${VAR} in api_key.
        # Keep the native provider name so mixed-protocol models select the right wire format.
        {
          name = "opencode-go";
          base_url = opencodeGoEndpoint;
          key_env = "OPENCODE_GO_API_KEY";
          discover_models = true;
        }

        # The router must allow model autoloading for /model switches.
        # Discovery requires a nonempty key; llama-server ignores the dummy value.
        {
          name = "llama";
          base_url = "http://192.168.0.101:8080/v1";
          api_key = "sk-local";
          discover_models = true;
        }
      ];

      # Main chat and unpinned delegates share this fallback route.
      fallback_providers = [
        commandcodeFlashTarget
      ];

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

      # Keep the media-mcp agent plugin disabled to avoid duplicate tool registration.
      # Commands run inside the container; Hermes expands credentials from .env.
      # qB exposes only the bounded operations listed below.
      mcp_servers = {
        lrr_readonly = {
          command = "/data/workspace/media-mcp/.venv/bin/media-mcp-lrr";
          args = [ ];
          env = {
            LRR_URL = "http://192.168.0.211:3001";
          };
          connect_timeout = 15;
          timeout = 120;
          sampling.enabled = false;
          tools = {
            include = [
              "server_info"
              "list_archives"
              "search_archives"
              "get_archive"
              "get_files"
              "fingerprint_page"
            ];
            prompts = false;
            resources = false;
          };
        };

        qb_bounded = {
          command = "/data/workspace/media-mcp/.venv/bin/media-mcp-qb";
          args = [ ];
          env = {
            QB_URL = "\${QB_URL}";
            QB_USER = "\${QB_USER}";
            QB_PASS = "\${QB_PASS}";
          };
          connect_timeout = 15;
          timeout = 120;
          sampling.enabled = false;
          tools = {
            include = [
              "server_version"
              "queue_preferences"
              "list_torrents"
              "get_torrent"
              "queue_diagnosis"
              "pause_torrent"
              "resume_torrent"
            ];
            prompts = false;
            resources = false;
          };
        };
      };
    };

    extraPackages = with pkgs; [
      # The sealed Hermes environment supplies Python; avoid a second interpreter closure.
      uv
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

    # Sealed uv2nix venv — lazy-install cannot write to a NixOS-managed
    # site-packages, so extras must be baked here. This list REPLACES the
    # upstream `default` package's own list rather than extending it.
    #
    # messaging: Telegram adapter's `from telegram import …`.
    # anthropic: the vision route (opencode-go/qwen3.8-flash) speaks Anthropic
    # Messages; without the SDK it logs "Failed to build Anthropic client …
    # falling back to OpenAI-wire".
    extraDependencyGroups = [
      "messaging"
      "anthropic"
    ];

  };

  # A bind taken before /mnt/data is up captures the empty mountpoint instead
  # of the virtiofs share. RequiresMountsFor implies Requires/After on
  # mnt-data.mount (jellyfin.nix:101).
  systemd.services.hermes-agent.unitConfig.RequiresMountsFor = [ mediaRoot ];

  # Reconcile named profiles before Gateway startup.
  # A separate unit keeps failures local to Hermes instead of aborting activation.
  systemd.services.hermes-agent-profile-settings = {
    description = "Nix-managed Hermes Profile settings, SOULs, and plugin links";
    wantedBy = [ "multi-user.target" ];
    before = [ "hermes-agent.service" ];
    requiredBy = [ "hermes-agent.service" ];
    path = [ pkgs.coreutils ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      hermes_home=${config.services.hermes-agent.stateDir}/.hermes

      # hermes-lcm plugin install (flake-pinned, materialized copy) — the
      # why-not-a-symlink story is in hermes-lcm.nix.
      ${hermesLcm.installScript}

      profiles_root=$hermes_home/profiles

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

          # Refresh shared skills while preserving each profile's dot-prefixed state.
          ${pkgs.rsync}/bin/rsync -a --delete --exclude='/.*' \
            "$hermes_home/skills/" "$profile_dir/skills/"
        '') specialistProfileAssets
      )}

    '';
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
