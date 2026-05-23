{
  config,
  lib,
  pkgs,
  hostname,
  source,
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
  ...
}:
let
  skillAllowlistShell =
    if skillAllowlist == null then "" else lib.concatStringsSep " " skillAllowlist;

  commandDenylistShell = lib.concatStringsSep " " commandDenylist;

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

  defaultHooks = {
    PreToolUse = [
      {
        matcher = "Bash";
        hooks = [
          {
            type = "command";
            command = "${config.home.homeDirectory}/.claude/hooks/block-destructive.sh";
          }
        ];
      }
    ];
  };

  mergedHooks =
    (lib.mapAttrs (event: defaults: defaults ++ (extraHooks.${event} or [ ])) defaultHooks)
    // (lib.removeAttrs extraHooks (lib.attrNames defaultHooks));

  settings = {
    hooks = mergedHooks;
    enabledPlugins = {
      "rust-analyzer-lsp@claude-plugins-official" = true;
      "context7@claude-plugins-official" = true;
      "commit-commands@claude-plugins-official" = true;
      "security-guidance@claude-plugins-official" = true;
      "greptile@claude-plugins-official" = false;
      "frontend-design@claude-plugins-official" = true;
      "pyright-lsp@claude-plugins-official" = true;
      "clangd-lsp@claude-plugins-official" = true;
      "andrej-karpathy-skills@karpathy-skills" = true;
      "superpowers@claude-plugins-official" = true;
      "github@claude-plugins-official" = true;
    };
    extraKnownMarketplaces = {
      karpathy-skills = {
        source = {
          source = "github";
          repo = "forrestchang/andrej-karpathy-skills";
        };
      };
    };
    effortLevel = "high";
    editorMode = "normal";
    skipAutoPermissionPrompt = true;
  };
in
{
  home.file.".claude/hooks" = {
    source = ./hooks;
    recursive = true;
    force = true;
  };

  home.file.".claude/settings.json" = {
    source = pkgs.writeText "claude-settings.json" (builtins.toJSON settings);
    force = true;
  };

  # User-authored skills kept in this repo (not from the ECC source flake).
  # link_children only sweeps symlinks pointing at $REPO/*, so a Nix-managed
  # skill directory here coexists with the allowlisted ECC skill symlinks.
  home.file.".claude/skills/fable-writing" = {
    source = ./skills/fable-writing;
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
          link_children "$REPO/rules"    "$CLAUDE/rules"

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
  );
}
