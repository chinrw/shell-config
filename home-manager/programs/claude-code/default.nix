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
  # Default set = used-in-past-sessions + ECC-tagged + user-curated workflows
  # + their direct SKILL.md references (transitive closure not taken; the
  # configure-ecc installer catalog is intentionally excluded to avoid
  # re-linking every skill it advertises).
  # Plugin and built-in skills are unaffected; see commandDenylist below.
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
    "deep-research"
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
  ],
  ...
}:
let
  skillAllowlistShell =
    if skillAllowlist == null then "" else lib.concatStringsSep " " skillAllowlist;

  commandDenylistShell = lib.concatStringsSep " " commandDenylist;

  ruleDenylistShell = lib.concatStringsSep " " ruleDenylist;

  baseClaudeMd = builtins.readFile ./CLAUDE.md;
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
      # Hide the 7d window unless usage hits 100%; keep the 5h window visible.
      sevenDayThreshold = 100;
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
    enabledPlugins = {
      "rust-analyzer-lsp@claude-plugins-official" = true;
      "context7@claude-plugins-official" = true;
      "commit-commands@claude-plugins-official" = true;
      "security-guidance@claude-plugins-official" = true;
      "frontend-design@claude-plugins-official" = true;
      "pyright-lsp@claude-plugins-official" = true;
      "clangd-lsp@claude-plugins-official" = true;
      "andrej-karpathy-skills@karpathy-skills" = true;
      "superpowers@claude-plugins-official" = true;
      "github@claude-plugins-official" = true;
      "claude-hud@claude-hud" = true;
    };
    extraKnownMarketplaces = {
      karpathy-skills = {
        source = {
          source = "github";
          repo = "forrestchang/andrej-karpathy-skills";
        };
      };
      claude-hud = {
        source = {
          source = "github";
          repo = "jarrodwatts/claude-hud";
        };
      };
    };
    skipAutoPermissionPrompt = true;
    # Deny access to secret-bearing paths natively. Read() rules cover the
    # Read/Grep/Glob tools and Claude-recognised Bash file commands (cat, head,
    # tail, sed); Edit() rules cover the built-in file editors. This replaces
    # the old block-destructive.sh hook, whose file-path checks never fired
    # because it was registered with a Bash-only matcher. Residual gap: `less`
    # and scripts that open files themselves (python/node) are NOT covered —
    # closing that needs the OS-level sandbox (sandbox.filesystem.denyRead).
    permissions = {
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
    # Drop descriptions for high-inbound hubs and isolated leaves to reclaim
    # system-prompt tokens. Names stay listed so cross-skill references and
    # slash-command invocations keep working.
    skillOverrides = {
      "verification-loop" = "name-only";
      "tdd-workflow" = "name-only";
      "knowledge-ops" = "name-only";
      "configure-ecc" = "name-only";
      "autonomous-agent-harness" = "name-only";
      "context-budget" = "name-only";
      "plan-orchestrate" = "name-only";
      "design-system" = "name-only";
      "hermes-imports" = "name-only";
      "plankton-code-quality" = "name-only";
      "product-capability" = "name-only";
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
            # duplicate Claude Code built-ins.
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
  );
}
