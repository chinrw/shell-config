{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Skills installed into both ~/.agents/skills and ~/.claude/skills.
  # mattpocock-skills are omitted from ~/.claude/skills because Claude Code
  # installs them through the mattpocock-skills@mattpocock plugin instead.
  directSharedSkills = [
    {
      name = "humanizer";
      source = inputs.humanizer;
    }
    {
      name = "stop-that-shit";
      source = "${inputs.stop-that-shit}/skills/stop-that-shit";
    }
    {
      name = "aihot";
      source = "${inputs.khazix-skills}/aihot";
      # Existing generations materialized these two directories; replacing a
      # directory with a symlink fails Home Manager's checkLinkTargets pass.
      claudeRecursive = true;
    }
    {
      name = "neat-freak";
      source = "${inputs.khazix-skills}/neat-freak";
      claudeRecursive = true;
    }
    {
      name = "agent-browser";
      source = ./agent-skills/agent-browser;
    }
  ];

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

  # ~/.agents/skills is shared across harnesses and has no allowlist, so drop
  # skills that should not be resident everywhere: pr imposes a fixed PR
  # template that conflicts with per-repo rules, and setup-matt-pocock-skills
  # is a one-off per-repo bootstrap.
  agentSkillDenylist = [
    "pr"
    "setup-matt-pocock-skills"
  ];

  agentSkillSourceOverrides = {
    research = ./agent-skills/research;
  };

  agentSkillSources =
    let
      upstreamSources =
        map (skill: { inherit (skill) name source; }) directSharedSkills ++ mattSkillSources;
      upstreamNames = map (skill: skill.name) upstreamSources;
      sources =
        builtins.listToAttrs (
          map (skill: {
            inherit (skill) name;
            value = skill.source;
          }) upstreamSources
        )
        // agentSkillSourceOverrides;
      names =
        upstreamNames ++ lib.subtractLists upstreamNames (builtins.attrNames agentSkillSourceOverrides);
    in
    assert lib.length upstreamNames == lib.length (lib.unique upstreamNames);
    map (name: {
      inherit name;
      source = sources.${name};
    }) (lib.filter (name: !(lib.elem name agentSkillDenylist)) names);

  agentSkillLinkCommands = lib.concatMapStrings (skill: ''
    register_agent_skill ${lib.escapeShellArg skill.name} ${lib.escapeShellArg skill.source}
  '') agentSkillSources;
in
{
  imports = [ inputs.agent-skills.homeManagerModules.default ];

  programs.agent-skills.enable = true;

  home.file = builtins.listToAttrs (
    map (skill: {
      name = ".claude/skills/${skill.name}";
      value = {
        inherit (skill) source;
      }
      // lib.optionalAttrs (skill.claudeRecursive or false) {
        recursive = true;
      };
    }) directSharedSkills
  );

  home.activation.sharedAgentSkills = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    (
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
          echo "agent-skills activation: duplicate agent skill basename: $name" >&2
          exit 1
        fi
        agent_skill_sources["$name"]="$src"
      }

      ${agentSkillLinkCommands}

      # The manifest identifies links made by this activation so stale links
      # are pruned after revision changes without touching manual entries.
      if [ -f "$AGENTS_MANIFEST" ]; then
        while IFS="$(printf '\t')" read -r old_name old_src; do
          [ -n "$old_name" ] || continue
          if [ -z "$old_src" ]; then
            echo "agent-skills activation: malformed agent skill manifest entry: $old_name" >&2
            exit 1
          fi
          old_target="$AGENTS_SKILLS/$old_name"
          if [ -L "$old_target" ]; then
            current_src="$(${pkgs.coreutils}/bin/readlink "$old_target")"
            if [ -n "''${agent_skill_sources[$old_name]+set}" ]; then
              expected_src="''${agent_skill_sources[$old_name]}"
              if [ "$current_src" != "$old_src" ] && [ "$current_src" != "$expected_src" ]; then
                echo "agent-skills activation: managed agent skill target $old_target points elsewhere" >&2
                exit 1
              fi
              if [ "$current_src" = "$old_src" ] && [ "$current_src" != "$expected_src" ]; then
                run ${pkgs.coreutils}/bin/rm "$old_target"
              fi
            elif [ "$current_src" != "$old_src" ]; then
              echo "agent-skills activation: managed agent skill target $old_target points elsewhere" >&2
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
          echo "agent-skills activation: agent skill source is not a directory: $src" >&2
          exit 1
        }
        [ -f "$src/SKILL.md" ] || {
          echo "agent-skills activation: agent skill source has no SKILL.md: $src" >&2
          exit 1
        }
        if [ -L "$target" ]; then
          current_src="$(${pkgs.coreutils}/bin/readlink "$target")"
          if [ "$current_src" != "$src" ]; then
            echo "agent-skills activation: agent skill target $target points elsewhere" >&2
            exit 1
          fi
        elif [ -e "$target" ]; then
          return 0
        else
          run ${pkgs.coreutils}/bin/ln -s "$src" "$target"
        fi
        managed_agent_skills["$name"]="$src"
      }

      for name in "''${!agent_skill_sources[@]}"; do
        link_agent_skill "$name" "''${agent_skill_sources[$name]}"
      done

      # Guard the rewrite on a live run: mktemp and redirection touch the
      # filesystem directly and would fail or leave temp files under --dry-run.
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
    )
  '';

  # Both ~/.claude/skills setup and ~/.agents/.shell-config-managed-skills
  # pruning must finish before agent-skills adopts or updates links.
  home.activation.agentSkills = lib.hm.dag.entryAfter [
    "claudeCodeAssets"
    "sharedAgentSkills"
  ] (lib.mkDefault "");
}
