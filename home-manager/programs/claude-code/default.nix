{
  config,
  lib,
  pkgs,
  hostname,
  source,
  inputs,
  mcpServers ? { },
  extraHooks ? { },
  extraInstructions ? "",
  # Skill allowlist: names linked into ~/.claude/skills/.
  # null = link every skill from the source flake (legacy behavior).
  # Every entry here stays LINKED and therefore explicitly invocable. Whether
  # its description also reaches the system prompt is decided separately by
  # skillOverrides below -- a skill must be linked before an override can
  # apply to it, so trimming this list and setting "name-only" are mutually
  # exclusive, not complementary.
  # Plugin and built-in skills are unaffected; see commandDenylist below.
  # Skills from other flake inputs (khazix-skills, mtg-agent-skill) are
  # installed by a different mechanism and are NOT filtered by this list.
  skillAllowlist ? [
    "agent-sort"
    "agentic-engineering"
    "api-connector-builder"
    "automation-audit-ops"
    "autonomous-agent-harness"
    "autonomous-loops"
    "benchmark"
    "code-tour"
    "codebase-onboarding"
    "coding-standards"
    "configure-ecc"
    "context-budget"
    "continuous-agent-loop"
    "continuous-learning-v2"
    "council"
    "dashboard-builder"
    "design-system"
    "django-patterns"
    "documentation-lookup"
    "ecc-guide"
    "ecc-tools-cost-audit"
    "eval-harness"
    "exa-search"
    "frontend-patterns"
    "git-workflow"
    "github-ops"
    "hermes-imports"
    "iterative-retrieval"
    "knowledge-ops"
    "nanoclaw-repl"
    "plan-orchestrate"
    "plankton-code-quality"
    "product-capability"
    "project-flow-ops"
    "python-patterns"
    "python-testing"
    "ralphinho-rfc-pipeline"
    "research-ops"
    "rust-patterns"
    "search-first"
    "security-bounty-hunter"
    "security-review"
    "security-scan"
    "skill-stocktake"
    "strategic-compact"
    "tdd-workflow"
    "terminal-ops"
    "verification-loop"
    "workspace-surface-audit"
  ],
  # Command denylist: basenames under $REPO/commands/ NOT linked into
  # ~/.claude/commands/. Commands are otherwise linked wholesale (no
  # allowlist). Use this to drop commands that duplicate Claude Code
  # built-ins. Empty list = link every command.
  commandDenylist ? [
    "aside.md"
    "checkpoint.md"
    "code-review.md"
    "plan.md"
    "review-pr.md"
  ],
  # Rule denylist: subdirectory names (or filenames) under $REPO/rules/
  # NOT linked into ~/.claude/rules/. Rules are otherwise linked wholesale
  # (no allowlist). Use this to drop unscoped rule packs (those without
  # `paths:` frontmatter) that would otherwise load as memory for every
  # project regardless of stack. Language-specific dirs declare `paths:`
  # and self-gate, so they don't need to be listed here. Empty list =
  # link every entry under $REPO/rules/.
  ruleDenylist ? [
    "zh"
    # Install documentation for the rule bundle itself (directory tree,
    # install.sh usage, "Adding a New Language"). No behavioural guidance, but
    # it sits at rules/ root without `paths:` frontmatter, so it loaded as
    # always-on memory in every project.
    "README.md"
    # Mandates `<type>: <description>` unconditionally, which contradicts the
    # repo-adaptive prefix rule in agent-instructions/git-commits.md. Both load
    # as always-on memory, so Claude would get two opposing commit rules —
    # and only Claude, since Codex and opencode never see the ECC bundle.
    "common/git-workflow.md"
  ],
  ...
}:
let
  claudeCodePackage = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;

  skillAllowlistShell =
    if skillAllowlist == null then "" else lib.concatStringsSep " " skillAllowlist;

  commandDenylistShell = lib.concatStringsSep " " commandDenylist;

  ruleDenylistShell = lib.concatStringsSep " " ruleDenylist;

  mattSkillSources =
    let
      skillsIn =
        category:
        let
          root = "${inputs.mattpocock-skills}/skills/${category}";
          entries = builtins.readDir root;
        in
        map
          (name: {
            inherit name;
            source = "${root}/${name}";
          })
          (
            lib.filter (
              name: builtins.getAttr name entries == "directory" && builtins.pathExists "${root}/${name}/SKILL.md"
            ) (builtins.attrNames entries)
          );
    in
    skillsIn "engineering" ++ skillsIn "productivity";

  # ~/.agents/skills is the Agent-Skills convention shared by Codex and other
  # harnesses (upstream's own scripts/link-skills.sh links the same two promoted
  # buckets there). Unlike ~/.claude/skills it has no allowlist, so this is the
  # one place to drop a skill that should not be resident in every harness.
  # Whether a skill is model- or user-invocable is settled by its own
  # frontmatter (`disable-model-invocation`) plus agents/openai.yaml, so this
  # list is only for skills that do not belong here at all.
  #
  # setup-matt-pocock-skills scaffolds per-repo configuration for the other
  # engineering skills. It is run once per repository, so a permanent global
  # link is noise.
  #
  # Not excluded, but worth knowing about: grill-me and grill-with-docs are
  # narrower siblings of grilling, and aihot is also linked into
  # ~/.claude/skills below.
  agentSkillDenylist = [
    "setup-matt-pocock-skills"
  ];

  agentSkillSources =
    let
      sources = lib.filter (skill: !(lib.elem skill.name agentSkillDenylist)) (
        [
          {
            name = "aihot";
            source = "${inputs.khazix-skills}/aihot";
          }
          # Codex CLI port of babysit-prs (github:chinrw/agent-skills). Lives in
          # ~/.agents/skills only — the Claude Code variant of the same repo is
          # linked into ~/.claude/skills by the activation below.
          {
            name = "babysit-prs-codex";
            source = "${inputs.agent-skills}/codex-skills/babysit-prs-codex";
          }
        ]
        ++ mattSkillSources
      );
    in
    assert lib.length sources == lib.length (lib.unique (map (skill: skill.name) sources));
    sources;

  agentSkillLinkCommands = lib.concatMapStrings (skill: ''
    register_agent_skill ${lib.escapeShellArg skill.name} ${lib.escapeShellArg skill.source}
  '') agentSkillSources;

  # Claude-specific rules first, then the rules Codex and opencode also get.
  sharedAgentInstructions = import ../agent-instructions { inherit lib pkgs; };
  # The activation below rewrites CLAUDE.md on every switch. Say so in the file
  # itself: the pointer to CLAUDE.local.md otherwise lives only in that file,
  # which is the one nobody opens before hand-editing CLAUDE.md.
  claudeMdBanner = ''
    <!-- Generated by home-manager from shell-config/home-manager/programs/claude-code/.
         Edits here are lost on the next switch. Host-local rules go in
         ~/.claude/CLAUDE.local.md. -->
  '';
  baseClaudeMd = claudeMdBanner + "\n" + builtins.readFile ./CLAUDE.md + "\n" + sharedAgentInstructions.text;
  withHostExtra =
    if extraInstructions == "" then
      baseClaudeMd
    else
      baseClaudeMd + "\n\n## Host-specific (${hostname})\n\n" + extraInstructions;
  baseClaudeMdFile = pkgs.writeText "claude-md-base" withHostExtra;

  mcpServersFile =
    if mcpServers == { } then
      null
    else
      pkgs.writeText "claude-mcp-servers.json" (builtins.toJSON mcpServers);

  mcpActivation = lib.optionalString (mcpServers != { }) ''
    CLAUDE_JSON="$HOME/.claude.json"
    TMP="$(${pkgs.coreutils}/bin/mktemp -p "$(${pkgs.coreutils}/bin/dirname "$CLAUDE_JSON")")"
    if [ -f "$CLAUDE_JSON" ]; then
      if ! ${pkgs.jq}/bin/jq --slurpfile m ${mcpServersFile} \
        '.mcpServers = $m[0]' "$CLAUDE_JSON" > "$TMP"; then
        ${pkgs.coreutils}/bin/rm -f "$TMP"
        echo "claude-code activation: jq merge into ~/.claude.json failed; original file left unchanged" >&2
        exit 1
      fi
    else
      if ! ${pkgs.jq}/bin/jq -n --slurpfile m ${mcpServersFile} \
        '{ mcpServers: $m[0] }' > "$TMP"; then
        ${pkgs.coreutils}/bin/rm -f "$TMP"
        echo "claude-code activation: jq creation of ~/.claude.json failed" >&2
        exit 1
      fi
    fi
    run ${pkgs.coreutils}/bin/mv "$TMP" "$CLAUDE_JSON"
  '';

  # No bundled default hooks. The former PreToolUse "block-destructive.sh"
  # guard was dropped in favour of native protection: secret-file access is
  # denied through settings.permissions.deny (below) — which, unlike the old
  # Bash-matcher hook, actually covers the Read/Edit tools and Claude's Bash
  # file commands — and destructive shell commands fall through to the normal
  # permission prompt. Per-host hooks still merge in via the extraHooks arg.
  defaultHooks = { };

  mergedHooks =
    (lib.mapAttrs (event: defaults: defaults ++ (extraHooks.${event} or [ ])) defaultHooks)
    // (lib.removeAttrs extraHooks (lib.attrNames defaultHooks));

  # statusLine wrapper for the claude-hud plugin. The plugin is installed by
  # Claude Code itself into ~/.claude/plugins/cache/<marketplace>/claude-hud/<version>/,
  # so the path is discovered dynamically at runtime. COLUMNS is exported so the
  # HUD knows the real terminal width — Claude Code pipes the subprocess stdout,
  # which makes process.stdout.columns unavailable.
  claudeHudStatusline = pkgs.writeShellScript "claude-hud-statusline" ''
    cols=$(${pkgs.coreutils}/bin/stty size </dev/tty 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $2}')
    export COLUMNS=$(( ''${cols:-120} > 4 ? ''${cols:-120} - 4 : 1 ))
    plugin_dir=$(${pkgs.coreutils}/bin/ls -d "''${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/claude-hud/*/ 2>/dev/null \
      | ${pkgs.gawk}/bin/awk -F/ '{ print $(NF-1) "\t" $0 }' \
      | ${pkgs.gnugrep}/bin/grep -E '^[0-9]+\.[0-9]+\.[0-9]+[[:space:]]' \
      | ${pkgs.coreutils}/bin/sort -t. -k1,1n -k2,2n -k3,3n -k4,4n \
      | ${pkgs.coreutils}/bin/tail -1 \
      | ${pkgs.coreutils}/bin/cut -f2-)
    [ -n "$plugin_dir" ] || exit 0
    exec ${pkgs.nodejs}/bin/node "''${plugin_dir}dist/index.js"
  '';

  claudeHudConfig = {
    lineLayout = "compact";
    showSeparators = true;
    display = {
      showTools = false;
      showAgents = true;
      # Hide the 7d window unless usage hits 100%; keep the 5h window visible.
      sevenDayThreshold = 100;
    };
    gitStatus = {
      enabled = true;
      showDirty = true;
      showAheadBehind = true;
      showFileStats = false;
    };
  };

  # Plugin enablement declared by Nix. Rendered into settings.json as
  # enabledPlugins (enforcedSettings below) AND consumed by
  # pluginBootstrapActivation, because the settings key alone installs
  # nothing: user-scope enabledPlugins only toggles plugins already present in
  # Claude Code's mutable plugin registry (managed settings are the only scope
  # with documented auto-install), so a fresh host needs the explicit
  # bootstrap. false = keep installed but disabled; false entries are not
  # bootstrapped.
  declaredPlugins = {
    "rust-analyzer-lsp@claude-plugins-official" = true;
    "context7@claude-plugins-official" = true;
    "commit-commands@claude-plugins-official" = true;
    "security-guidance@claude-plugins-official" = true;
    "frontend-design@claude-plugins-official" = true;
    "pyright-lsp@claude-plugins-official" = true;
    "clangd-lsp@claude-plugins-official" = true;
    "andrej-karpathy-skills@karpathy-skills" = true;
    "mattpocock-skills@mattpocock" = true;
    "superpowers@claude-plugins-official" = false;
    "github@claude-plugins-official" = true;
    "codex@openai-codex" = true;
    "claude-hud@claude-hud" = true;
  };

  # Third-party marketplaces backing the plugins above. Rendered into
  # settings.json as extraKnownMarketplaces AND used by
  # pluginBootstrapActivation — the settings key only declares a trusted name
  # for the CLI, it never clones the marketplace repo.
  declaredMarketplaces = {
    karpathy-skills = {
      source = {
        source = "github";
        repo = "forrestchang/andrej-karpathy-skills";
      };
    };
    mattpocock = {
      source = {
        source = "github";
        repo = "mattpocock/skills";
      };
    };
    claude-hud = {
      source = {
        source = "github";
        repo = "jarrodwatts/claude-hud";
      };
    };
    openai-codex = {
      source = {
        source = "github";
        repo = "openai/codex-plugin-cc";
      };
    };
  };

  # Structural settings Nix always owns. These are re-asserted on every switch
  # (enforced wins the merge in settingsActivation below). Runtime-mutable keys
  # like effortLevel / model / editorMode are intentionally NOT here — they live
  # in seedSettings and are preserved across switches.
  enforcedSettings = {
    hooks = mergedHooks;
    statusLine = {
      type = "command";
      command = "${claudeHudStatusline}";
    };
    enabledPlugins = declaredPlugins;
    extraKnownMarketplaces = declaredMarketplaces;
    skipAutoPermissionPrompt = true;
    # Stop Claude Code appending a `Co-Authored-By: Claude` trailer to commits.
    # CLAUDE.md already forbids it, but that relies on the model complying every
    # time; this suppresses the trailer at the source.
    includeCoAuthoredBy = false;
    # Deny access to secret-bearing paths natively. Read() rules cover the
    # Read/Grep/Glob tools and Claude-recognised Bash file commands (cat, head,
    # tail, sed); Edit() rules cover the built-in file editors. This replaces
    # the old block-destructive.sh hook, whose file-path checks never fired
    # because it was registered with a Bash-only matcher. Residual gap: `less`
    # and scripts that open files themselves (python/node) are NOT covered —
    # closing that needs the OS-level sandbox (sandbox.filesystem.denyRead).
    permissions = {
      # Delegate routine per-action approvals to the safety classifier instead
      # of prompting for each one. This MUST be asserted from a user-scope
      # settings file (which ~/.claude/settings.json is): Claude Code ignores
      # a defaultMode of "auto" coming from repo-controllable project settings.
      # Not a lock-in -- if auto mode is unavailable at startup (unsupported
      # model, org kill switch), the CLI falls back to default mode with a
      # notice.
      defaultMode = "auto";
      deny = [
        "Read(.env)"
        "Read(.env.*)"
        "Read(id_rsa)"
        "Read(credentials.json)"
        "Read(.git/**)"
        "Read(~/.ssh/**)"
        "Edit(.env)"
        "Edit(.env.*)"
        "Edit(id_rsa)"
        "Edit(credentials.json)"
        "Edit(.git/**)"
        "Edit(~/.ssh/**)"
      ];
    };
    # Per-skill listing overrides. From Claude Code's own settings schema:
    #   absent                = listed with description; model may auto-invoke.
    #   "name-only"           = listed without description; model may still
    #                           auto-invoke it by name. Costs ~4-5 tokens.
    #   "user-invocable-only" = hidden from the model entirely, `/name` still
    #                           works. Costs nothing.
    #   "off"                 = hidden from both; `/name` stops working.
    #
    # Audited over 311 recorded sessions: the only ECC skills ever invoked are
    # codebase-onboarding (1) and hermes-imports (4). neat-freak (9) ships from
    # a different flake input and is not affected by this list.
    #
    # Everything below is "user-invocable-only": reachable on demand via
    # `/<name>`, invisible to the model, zero resident tokens. The tradeoff is
    # that these skills can no longer delegate to each other via the Skill tool
    # (72 such references exist among them). That is acceptable because none has
    # ever been invoked -- but if you start using one, flip whichever skill it
    # delegates to back to "name-only" so the model can reach it.
    #
    # hermes-imports is the exception: transcripts show it is model-invoked
    # (4 sessions) rather than slash-invoked, so hiding it from the model would
    # stop it firing. It stays "name-only".
    # codebase-onboarding is also model-invoked, and keeps its description.
    skillOverrides = {
      "hermes-imports" = "name-only";

      # khazix-skills. Installed via home.file (below), NOT via skillAllowlist,
      # so these keys are deliberately absent from that list. Their descriptions
      # are natural-language trigger text, so hiding them from the model also
      # stops the Chinese-phrase auto-triggering they were written for --
      # invoke them with `/<name>` instead. Note hv-analysis points at
      # khazix-writer for style definitions; with both hidden from the model
      # that pointer resolves by reading the file, not by Skill invocation.
      #
      # The sibling khazix/mtg skills fable-writing, mtg-card-evaluation and
      # mtg-deck-analysis need no entry: they set `disable-model-invocation:
      # true` in their own frontmatter, which Claude Code already resolves to
      # user-invocable-only (source: "author").
      "aihot" = "user-invocable-only";
      "hv-analysis" = "user-invocable-only";
      "khazix-writer" = "user-invocable-only";
      "storage-analyzer" = "user-invocable-only";

      "agent-sort" = "user-invocable-only";
      "agentic-engineering" = "user-invocable-only";
      "api-connector-builder" = "user-invocable-only";
      "automation-audit-ops" = "user-invocable-only";
      "autonomous-agent-harness" = "user-invocable-only";
      "autonomous-loops" = "user-invocable-only";
      "benchmark" = "user-invocable-only";
      "code-tour" = "user-invocable-only";
      "coding-standards" = "user-invocable-only";
      "configure-ecc" = "user-invocable-only";
      "context-budget" = "user-invocable-only";
      "continuous-agent-loop" = "user-invocable-only";
      "continuous-learning-v2" = "user-invocable-only";
      "council" = "user-invocable-only";
      "dashboard-builder" = "user-invocable-only";
      "design-system" = "user-invocable-only";
      "django-patterns" = "user-invocable-only";
      "documentation-lookup" = "user-invocable-only";
      "ecc-guide" = "user-invocable-only";
      "ecc-tools-cost-audit" = "user-invocable-only";
      "eval-harness" = "user-invocable-only";
      "exa-search" = "user-invocable-only";
      "frontend-patterns" = "user-invocable-only";
      "git-workflow" = "user-invocable-only";
      "github-ops" = "user-invocable-only";
      "iterative-retrieval" = "user-invocable-only";
      "knowledge-ops" = "user-invocable-only";
      "nanoclaw-repl" = "user-invocable-only";
      "plan-orchestrate" = "user-invocable-only";
      "plankton-code-quality" = "user-invocable-only";
      "product-capability" = "user-invocable-only";
      "project-flow-ops" = "user-invocable-only";
      "python-patterns" = "user-invocable-only";
      "python-testing" = "user-invocable-only";
      "ralphinho-rfc-pipeline" = "user-invocable-only";
      "research-ops" = "user-invocable-only";
      "rust-patterns" = "user-invocable-only";
      "search-first" = "user-invocable-only";
      "security-bounty-hunter" = "user-invocable-only";
      "security-review" = "user-invocable-only";
      "security-scan" = "user-invocable-only";
      "skill-stocktake" = "user-invocable-only";
      "strategic-compact" = "user-invocable-only";
      "tdd-workflow" = "user-invocable-only";
      "terminal-ops" = "user-invocable-only";
      "verification-loop" = "user-invocable-only";
      "workspace-surface-audit" = "user-invocable-only";
    };
  };

  # Runtime-mutable defaults. Seeded into settings.json only when the file does
  # not already define them; once /effort, /model, or the vim toggle writes a
  # value, the existing file wins and the choice persists across switches.
  # (model is intentionally absent — we don't seed a default model.)
  seedSettings = {
    effortLevel = "high";
    editorMode = "normal";
  };

  enforcedSettingsFile = pkgs.writeText "claude-settings-enforced.json" (
    builtins.toJSON enforcedSettings
  );
  seedSettingsFile = pkgs.writeText "claude-settings-seed.json" (builtins.toJSON seedSettings);

  # Materialize ~/.claude/settings.json as a REAL, user-writable file instead of
  # a read-only Nix-store symlink. Claude Code writes this file at runtime
  # (/effort, /model, vim toggle); a store symlink makes those writes fail with
  # EROFS. The merge is (seed * existing) * enforced:
  #   - seed * existing : existing values win, so runtime tweaks persist; seed
  #                       only fills keys the file has never set.
  #   - * enforced      : Nix structural keys always win, so config updates
  #                       (plugins, hooks, permissions, statusline) propagate.
  settingsActivation = ''
    SETTINGS="${config.home.homeDirectory}/.claude/settings.json"
    # Strip a stale Nix-store symlink left by previous home.file management so we
    # can replace it with a writable file.
    if [ -L "$SETTINGS" ]; then
      case "$(${pkgs.coreutils}/bin/readlink "$SETTINGS")" in
        /nix/store/*) run ${pkgs.coreutils}/bin/rm "$SETTINGS" ;;
      esac
    fi
    SETTINGS_EXISTING="$(${pkgs.coreutils}/bin/mktemp -p "$(${pkgs.coreutils}/bin/dirname "$SETTINGS")")"
    if [ -f "$SETTINGS" ]; then
      ${pkgs.coreutils}/bin/cat "$SETTINGS" > "$SETTINGS_EXISTING"
    else
      ${pkgs.coreutils}/bin/printf '{}' > "$SETTINGS_EXISTING"
    fi
    SETTINGS_TMP="$(${pkgs.coreutils}/bin/mktemp -p "$(${pkgs.coreutils}/bin/dirname "$SETTINGS")")"
    if ${pkgs.jq}/bin/jq -s '(.[0] * .[1]) * .[2]' \
        ${seedSettingsFile} "$SETTINGS_EXISTING" ${enforcedSettingsFile} > "$SETTINGS_TMP"; then
      run ${pkgs.coreutils}/bin/mv "$SETTINGS_TMP" "$SETTINGS"
    else
      ${pkgs.coreutils}/bin/rm -f "$SETTINGS_TMP"
      ${pkgs.coreutils}/bin/rm -f "$SETTINGS_EXISTING"
      echo "claude-code activation: jq merge into settings.json failed; left unchanged" >&2
      exit 1
    fi
    ${pkgs.coreutils}/bin/rm -f "$SETTINGS_EXISTING"
  '';

  # Marketplaces the plugin bootstrap must ensure exist before installing.
  # Includes the official marketplace: Claude Code special-cases cloning it on
  # first interactive startup, but activation on a fresh host runs earlier
  # than that and the @claude-plugins-official installs below need it present.
  bootstrapMarketplaces = {
    claude-plugins-official = "anthropics/claude-plugins-official";
  }
  // lib.mapAttrs (_name: mp: mp.source.repo) declaredMarketplaces;

  bootstrapPlugins = lib.attrNames (lib.filterAttrs (_name: enabled: enabled) declaredPlugins);

  # Converge Claude Code's mutable plugin state with the declarations above.
  # Guards check the registry entry AND the defining content it points at,
  # not just that a directory exists: registry files and bare directories
  # survive cache wipes, interrupted clones, and partial restores, so neither
  # proves the marketplace/plugin is actually usable. A marketplace is healthy
  # only with its .claude-plugin/marketplace.json manifest; a plugin cache
  # only when it is a DIRECTORY with content — the -d test matters because
  # `ls -A` on a regular file prints the filename, which would pass the
  # non-empty check (no stronger universal marker exists — the LSP plugins
  # ship without a plugin.json). The repair command differs by state (each
  # verified against the CLI): `marketplace add` trusts the registry and
  # reports "already on disk" WITHOUT recloning a deleted or gutted
  # directory, so those states need `marketplace update`; `plugin install`
  # does re-fetch a deleted or emptied cache directory (it prints "already
  # installed" for the emptied case but still repopulates the files).
  # Every declared marketplace and enabled plugin additionally gets an
  # UNCONDITIONAL refresh/update pass on each switch — switch-time update,
  # same mental model as `nix flake update`. This deliberately includes the
  # official marketplace and its plugins: Claude Code's session-start update
  # sweep would normally cover those, but the claude-code-nix wrapper exports
  # DISABLE_AUTOUPDATER=1 (self-update cannot work from the read-only store)
  # and the docs say that disables the plugin sweep with it — so on these
  # hosts the switch is the only update path guaranteed by the documented
  # contract, for ALL plugins. Third-party marketplaces never auto-update
  # regardless (their autoUpdate flag is managed-settings-only). Explicit HTTPS clone URLs are deliberate —
  # the CLI's owner/repo shorthand clones over SSH, which fails on hosts
  # without GitHub keys. Every step warns instead of aborting so an offline
  # switch still succeeds and the next switch retries. The subshell keeps the
  # git PATH prefix (needed by the CLI's marketplace clone) out of later
  # activation steps.
  pluginBootstrapActivation = ''
    (
    export PATH="${pkgs.git}/bin:$PATH"
    CLAUDE_PLUGINS="${config.home.homeDirectory}/.claude/plugins"
  ''
  + lib.concatStrings (
    lib.mapAttrsToList (name: repo: ''
      mp_loc="$(${pkgs.jq}/bin/jq -r '."${name}".installLocation // ""' \
        "$CLAUDE_PLUGINS/known_marketplaces.json" 2>/dev/null || true)"
      if [ -z "$mp_loc" ]; then
        run ${claudeCodePackage}/bin/claude plugin marketplace add "https://github.com/${repo}" \
          || echo "claude-code activation: marketplace add ${name} failed; will retry next switch" >&2
      elif [ ! -f "$mp_loc/.claude-plugin/marketplace.json" ]; then
        run ${claudeCodePackage}/bin/claude plugin marketplace update "${name}" \
          || echo "claude-code activation: marketplace update ${name} failed; will retry next switch" >&2
      fi
    '') bootstrapMarketplaces
  )
  + lib.concatStrings (
    lib.mapAttrsToList (name: _repo: ''
      run ${claudeCodePackage}/bin/claude plugin marketplace update "${name}" \
        || echo "claude-code activation: marketplace refresh ${name} failed; will retry next switch" >&2
    '') bootstrapMarketplaces
  )
  + lib.concatMapStrings (key: ''
    plugin_loc="$(${pkgs.jq}/bin/jq -r \
      '.plugins["${key}"] // [] | map(select(.scope == "user")) | .[0].installPath // ""' \
      "$CLAUDE_PLUGINS/installed_plugins.json" 2>/dev/null || true)"
    if [ -z "$plugin_loc" ] || [ ! -d "$plugin_loc" ] \
      || [ -z "$(${pkgs.coreutils}/bin/ls -A "$plugin_loc" 2>/dev/null || true)" ]; then
      run ${claudeCodePackage}/bin/claude plugin install "${key}" --scope user \
        || echo "claude-code activation: plugin install ${key} failed; will retry next switch" >&2
    fi
  '') bootstrapPlugins
  + lib.concatMapStrings (key: ''
    run ${claudeCodePackage}/bin/claude plugin update "${key}" --scope user \
      || echo "claude-code activation: plugin update ${key} failed; will retry next switch" >&2
  '') bootstrapPlugins
  + ''
    )
  '';

  agentSkillsActivation = ''
    AGENTS="${config.home.homeDirectory}/.agents"
    AGENTS_SKILLS="$AGENTS/skills"
    AGENTS_MANIFEST="$AGENTS/.shell-config-managed-skills"

    run ${pkgs.coreutils}/bin/mkdir -p "$AGENTS_SKILLS"

    declare -A agent_skill_sources=()
    declare -A managed_agent_skills=()
    register_agent_skill() {
      local name="$1"
      local src="$2"
      if [ -n "''${agent_skill_sources[$name]+set}" ]; then
        echo "claude-code activation: duplicate agent skill basename: $name" >&2
        exit 1
      fi
      agent_skill_sources["$name"]="$src"
    }

    ${agentSkillLinkCommands}

    # The manifest identifies links made by this activation. It lets us prune
    # stale links after a source revision changes without touching unrelated
    # symlinks or manually managed non-symlink paths.
    if [ -f "$AGENTS_MANIFEST" ]; then
      while IFS="$(printf '\t')" read -r old_name old_src; do
        [ -n "$old_name" ] || continue
        if [ -z "$old_src" ]; then
          echo "claude-code activation: malformed agent skill manifest entry: $old_name" >&2
          exit 1
        fi
        old_target="$AGENTS_SKILLS/$old_name"
        if [ -L "$old_target" ]; then
          current_src="$(${pkgs.coreutils}/bin/readlink "$old_target")"
          if [ -n "''${agent_skill_sources[$old_name]+set}" ]; then
            expected_src="''${agent_skill_sources[$old_name]}"
            if [ "$current_src" != "$old_src" ] && [ "$current_src" != "$expected_src" ]; then
              echo "claude-code activation: managed agent skill target $old_target points elsewhere" >&2
              exit 1
            fi
            if [ "$current_src" = "$old_src" ] && [ "$current_src" != "$expected_src" ]; then
              run ${pkgs.coreutils}/bin/rm "$old_target"
            fi
          elif [ "$current_src" != "$old_src" ]; then
            echo "claude-code activation: managed agent skill target $old_target points elsewhere" >&2
            exit 1
          else
            run ${pkgs.coreutils}/bin/rm "$old_target"
          fi
        fi
      done < "$AGENTS_MANIFEST"
    fi

    link_agent_skill() {
      local name="$1"
      local src="$2"
      local target="$AGENTS_SKILLS/$name"
      [ -d "$src" ] || {
        echo "claude-code activation: agent skill source is not a directory: $src" >&2
        exit 1
      }
      [ -f "$src/SKILL.md" ] || {
        echo "claude-code activation: agent skill source has no SKILL.md: $src" >&2
        exit 1
      }
      if [ -L "$target" ]; then
        current_src="$(${pkgs.coreutils}/bin/readlink "$target")"
        if [ "$current_src" != "$src" ]; then
          echo "claude-code activation: agent skill target $target points elsewhere" >&2
          exit 1
        fi
      elif [ -e "$target" ]; then
        # Preserve manually managed files and directories.
        return 0
      else
        run ${pkgs.coreutils}/bin/ln -s "$src" "$target"
      fi
      managed_agent_skills["$name"]="$src"
    }

    for name in "''${!agent_skill_sources[@]}"; do
      link_agent_skill "$name" "''${agent_skill_sources[$name]}"
    done

    # Guard the whole rewrite on a live run rather than wrapping each step in
    # `run`: mktemp and the redirect below touch the filesystem directly, so
    # under --dry-run they would leave a stray temp file that the no-op `mv`
    # never collects -- and would fail outright on a host where ~/.agents does
    # not exist yet, because the mkdir above is itself a `run`.
    if [[ -v DRY_RUN ]]; then
      echo "would write $AGENTS_MANIFEST (''${#managed_agent_skills[@]} entries)"
    else
      AGENTS_MANIFEST_TMP="$(${pkgs.coreutils}/bin/mktemp "$AGENTS/.shell-config-managed-skills.XXXXXX")"
      {
        for name in "''${!managed_agent_skills[@]}"; do
          printf '%s\t%s\n' "$name" "''${managed_agent_skills[$name]}"
        done
      } | ${pkgs.coreutils}/bin/sort > "$AGENTS_MANIFEST_TMP"
      ${pkgs.coreutils}/bin/mv "$AGENTS_MANIFEST_TMP" "$AGENTS_MANIFEST"
    fi
  '';
in
{
  # settings.json is NOT managed via home.file (that produces a read-only store
  # symlink Claude Code cannot write to). It is built as a writable real file in
  # settingsActivation below. See the comment on settingsActivation for the
  # seed-vs-enforce merge rationale.

  # claude-hud reads this file at runtime to toggle optional HUD features.
  # The plugin's own state lives in sibling ~/.claude/plugins/claude-hud/config-cache/.
  home.file.".claude/plugins/claude-hud/config.json" = {
    source = pkgs.writeText "claude-hud-config.json" (builtins.toJSON claudeHudConfig);
    force = true;
  };

  # User-authored skills kept in this repo (not from the ECC source flake).
  # link_children only sweeps symlinks pointing at $REPO/*, so a Nix-managed
  # skill directory here coexists with the allowlisted ECC skill symlinks.
  home.file.".claude/skills/fable-writing" = {
    source = ./skills/fable-writing;
    recursive = true;
  };

  # User-authored slash command kept in this repo. Maps to user scope so `/ship`
  # is available in every repo. link_children only sweeps symlinks into $REPO
  # (the ECC source), so this Nix-managed file coexists with the ECC commands.
  home.file.".claude/commands/ship.md".source = ./commands/ship.md;

  # mtg-agent-skill repo contains two sibling skills at its root.
  # Map each subfolder into its own ~/.claude/skills/<name> location so the
  # folder name matches the `name:` field in each SKILL.md frontmatter.
  home.file.".claude/skills/mtg-deck-analysis" = {
    source = "${inputs.mtg-agent-skill}/mtg-deck-analysis";
    recursive = true;
  };

  home.file.".claude/skills/mtg-card-evaluation" = {
    source = "${inputs.mtg-agent-skill}/mtg-card-evaluation";
    recursive = true;
  };

  # khazix-skills repo hosts five sibling skills at its root. Each subfolder
  # name already matches the `name:` field in its SKILL.md frontmatter, so map
  # each into its own ~/.claude/skills/<name> location (same pattern as the mtg
  # skills above). link_children only sweeps symlinks into $REPO (the ECC
  # source), so these Nix-managed dirs coexist with the allowlisted ECC skills.
  home.file.".claude/skills/aihot" = {
    source = "${inputs.khazix-skills}/aihot";
    recursive = true;
  };

  home.file.".claude/skills/hv-analysis" = {
    source = "${inputs.khazix-skills}/hv-analysis";
    recursive = true;
  };

  home.file.".claude/skills/khazix-writer" = {
    source = "${inputs.khazix-skills}/khazix-writer";
    recursive = true;
  };

  home.file.".claude/skills/neat-freak" = {
    source = "${inputs.khazix-skills}/neat-freak";
    recursive = true;
  };

  home.file.".claude/skills/storage-analyzer" = {
    source = "${inputs.khazix-skills}/storage-analyzer";
    recursive = true;
  };

  home.activation.claudeCodeAssets = lib.hm.dag.entryAfter [ "linkGeneration" ] (
    ''
          REPO="${source}"
          CLAUDE="${config.home.homeDirectory}/.claude"

          link_children() {
            local src="$1"
            local dst="$2"
            # Optional 3rd arg: space-separated allowlist of basenames to keep.
            # When set, names outside the list are skipped and any existing
            # symlink at that target is removed so home-manager prunes
            # previously-linked entries.
            local allowlist="''${3-}"
            # Optional 4th arg: space-separated denylist of basenames to skip
            # even when no allowlist is set — used to drop commands that
            # duplicate Claude Code built-ins. An entry may name a path inside
            # a subdirectory ("common/git-workflow.md"); see the recursion below.
            local denylist="''${4-}"
            [ -d "$src" ] || return 0
            run mkdir -p "$dst"
            if [ -L "$dst" ]; then
              run rm "$dst"
              run mkdir -p "$dst"
            fi
            # Sweep stale symlinks. (a) Links into the current $REPO whose
            # target no longer exists (entries pruned/renamed upstream).
            # (b) ANY link into the legacy ~/Documents/play/everything-claude-code
            # clone — that path is no longer the managed source, so such links
            # are always stale even when the old clone still exists on disk.
            run ${pkgs.findutils}/bin/find "$dst" -maxdepth 1 -type l \
              -lname "$REPO/*" \
              -exec sh -c '[ ! -e "$1" ] && rm "$1"' _ {} \;
            run ${pkgs.findutils}/bin/find "$dst" -maxdepth 1 -type l \
              -lname "*/Documents/play/everything-claude-code/*" \
              -delete
            for entry in "$src"/*; do
              [ -e "$entry" ] || continue
              local name target
              name=$(basename "$entry")
              target="$dst/$name"
              if [ -n "$allowlist" ]; then
                case " $allowlist " in
                  *" $name "*) ;;
                  *)
                    # Not in allowlist: drop any pre-existing symlink so the
                    # next switch prunes it. Leave non-symlink files alone.
                    if [ -L "$target" ]; then
                      run rm "$target"
                    fi
                    continue
                    ;;
                esac
              fi
              if [ -n "$denylist" ]; then
                case " $denylist " in
                  *" $name "*)
                    # In denylist: drop any pre-existing symlink so the next
                    # switch prunes it. Leave non-symlink files alone.
                    if [ -L "$target" ]; then
                      run rm "$target"
                    fi
                    continue
                    ;;
                esac
              fi
              # A denylist entry naming a path inside this directory can't be
              # honoured by symlinking the directory itself. Recurse instead:
              # $target becomes a real directory holding one symlink per kept
              # child, so the rest of the upstream directory still applies.
              local nested=""
              for denied in $denylist; do
                case "$denied" in
                  "$name"/*) nested="$nested ''${denied#"$name"/}" ;;
                esac
              done
              if [ -n "$nested" ] && [ -d "$entry" ]; then
                link_children "$entry" "$target" "" "$nested"
                continue
              fi
              # Dropping the nested denylist entry must put the directory back,
              # or the removal is a one-way door: the plain symlink below never
              # runs while a real directory sits at $target. Recognise a
              # directory we materialised by its contents — every child is a
              # symlink into this same source — and clear it. A directory
              # holding anything else belongs to the user.
              if [ -z "$nested" ] && [ -d "$target" ] && [ ! -L "$target" ]; then
                local child link_target ours=1
                for child in "$target"/*; do
                  [ -e "$child" ] || [ -L "$child" ] || continue
                  if [ ! -L "$child" ]; then
                    ours=0
                    break
                  fi
                  link_target=$(${pkgs.coreutils}/bin/readlink "$child")
                  case "$link_target" in
                    "$entry"/*) ;;
                    *)
                      ours=0
                      break
                      ;;
                  esac
                done
                if [ "$ours" = 1 ]; then
                  run rm -rf "$target"
                fi
              fi
              # Don't clobber a non-symlink file at this path.
              if [ -e "$target" ] && [ ! -L "$target" ]; then
                continue
              fi
              run ln -sfn "$entry" "$target"
            done
          }

          link_children "$REPO/agents"   "$CLAUDE/agents"
          link_children "$REPO/commands" "$CLAUDE/commands" "" "${commandDenylistShell}"
          link_children "$REPO/skills"   "$CLAUDE/skills"   "${skillAllowlistShell}"
          link_children "$REPO/rules"    "$CLAUDE/rules"   "" "${ruleDenylistShell}"

          # agent-skills (github:chinrw/agent-skills): the user's own
          # version-controlled Claude Code skills and companion agents.
          # Linked with the same helper; $REPO is swapped so the stale-link
          # sweep matches this input's store path instead of the ECC source.
          # ln -sfn deliberately overwrites any working-copy links left by the
          # repository's own install.sh — Nix owns these paths now.
          ECC_REPO="$REPO"
          REPO="${inputs.agent-skills}"
          link_children "${inputs.agent-skills}/skills" "$CLAUDE/skills"
          link_children "${inputs.agent-skills}/agents" "$CLAUDE/agents"
          REPO="$ECC_REPO"

          CLAUDE_MD_BASE="${baseClaudeMdFile}"
          LOCAL_MD="$CLAUDE/CLAUDE.local.md"
          FINAL_MD="$CLAUDE/CLAUDE.md"

          # Seed CLAUDE.local.md on first run only — never touch existing user content.
          if [ ! -e "$LOCAL_MD" ] && [ ! -L "$LOCAL_MD" ]; then
            ${pkgs.coreutils}/bin/cat > "$LOCAL_MD" <<'EOF'
      <!--
      This file is local to this host and not tracked by Nix.
      Edits land in ~/.claude/CLAUDE.md after the next `home-manager switch`,
      appended below the Nix-managed base content.

      Use it for host-specific shortcuts, side-project context, or anything you
      want Claude to see at user scope but don't want to commit to the
      shell-config flake.

      Replace this comment with real content. Claude ignores HTML comments in
      markdown, so the seed text is not visible in CLAUDE.md until you replace it.
      -->
      EOF
          fi

          # Strip a previous Nix symlink at ~/.claude/CLAUDE.md if present, then rebuild.
          if [ -L "$FINAL_MD" ]; then
            case "$(${pkgs.coreutils}/bin/readlink "$FINAL_MD")" in
              /nix/store/*) run rm "$FINAL_MD" ;;
            esac
          fi

          TMP_MD="$(${pkgs.coreutils}/bin/mktemp -p "$(${pkgs.coreutils}/bin/dirname "$FINAL_MD")")"
          {
            ${pkgs.coreutils}/bin/cat "$CLAUDE_MD_BASE"
            if [ -s "$LOCAL_MD" ]; then
              printf '\n\n## Local additions (%s)\n\n' "${hostname}"
              ${pkgs.coreutils}/bin/cat "$LOCAL_MD"
            fi
          } > "$TMP_MD"
          run ${pkgs.coreutils}/bin/mv "$TMP_MD" "$FINAL_MD"
    ''
    + mcpActivation
    + settingsActivation
    + pluginBootstrapActivation
    + agentSkillsActivation
  );
}
