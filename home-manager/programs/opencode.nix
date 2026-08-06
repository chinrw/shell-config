{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Update with: nix flake update oh-my-opencode-slim
  packageVersion = source: (builtins.fromJSON (builtins.readFile "${source}/package.json")).version;
  ohMyOpenCodeSlimVersion = packageVersion inputs.oh-my-opencode-slim;
  bun2nixPackage = inputs.bun2nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  bunInstallFlags = [
    "--linker=hoisted"
  ]
  ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
    "--backend=copyfile"
  ];
  # Derive dependencies from each flake input's upstream bun.lock. This keeps
  # source and transitive dependencies in sync without a second lock file, and
  # lets one machine evaluate every target platform. Bun's text lock is JSON
  # with trailing commas, so strip only commas before a closing object or array.
  parseBunLock =
    source:
    let
      parts = builtins.split ",([[:space:]]*(}|]))" (builtins.readFile "${source}/bun.lock");
      json = builtins.concatStringsSep "" (
        map (part: if builtins.isList part then builtins.elemAt part 0 else part) parts
      );
    in
    builtins.fromJSON json;
  bunNixFromLock =
    name: source:
    let
      packageTuples = builtins.attrValues (parseBunLock source).packages;
      packageEntry =
        fetchurl: tuple:
        let
          package = if builtins.length tuple > 0 then builtins.elemAt tuple 0 else null;
          hash = if builtins.length tuple > 3 then builtins.elemAt tuple 3 else null;
          scoped =
            if builtins.isString package then builtins.match "^(@[^/]+/([^@]+))@(.+)$" package else null;
          unscoped = if builtins.isString package then builtins.match "^([^@]+)@(.+)$" package else null;
          packageInfo =
            if scoped != null then
              {
                registryName = builtins.elemAt scoped 0;
                tarballName = builtins.elemAt scoped 1;
                version = builtins.elemAt scoped 2;
              }
            else if unscoped != null then
              {
                registryName = builtins.elemAt unscoped 0;
                tarballName = builtins.elemAt unscoped 0;
                version = builtins.elemAt unscoped 1;
              }
            else
              null;
        in
        if packageInfo == null || !builtins.isString hash then
          throw "opencode: ${name} has a non-registry Bun dependency unsupported by the pure lock parser"
        else
          {
            name = package;
            value = fetchurl {
              url =
                "https://registry.npmjs.org/${packageInfo.registryName}/-/"
                + "${packageInfo.tarballName}-${packageInfo.version}.tgz";
              inherit hash;
            };
          };
    in
    { fetchurl, ... }:
    builtins.listToAttrs (map (packageEntry fetchurl) packageTuples);
  # `files` is upstream's own declaration of what a published copy needs at
  # runtime, so it is the authority on what belongs in the store output.
  packageFiles =
    source: (builtins.fromJSON (builtins.readFile "${source}/package.json")).files or [ ];
  mkBunPluginPackage =
    {
      pname,
      source,
      buildCommands ? "",
    }:
    let
      bunNix = bunNixFromLock pname source;
      runtimeFiles = packageFiles source;
    in
    bun2nixPackage.mkDerivation {
      inherit pname;
      version = packageVersion source;
      src = source;
      bunDeps = bun2nixPackage.fetchBunDeps { inherit bunNix; };
      inherit bunInstallFlags;
      dontRunLifecycleScripts = true;
      buildPhase = ''
        runHook preBuild
        ${buildCommands}
        runHook postBuild
      '';
      # Ship the published file set plus node_modules -- not the whole checkout,
      # which also carries docs/, img/, test/ and the repo's own lint/build
      # tooling config.
      #
      # node_modules stays complete on purpose. The bundles keep several
      # dependencies external, and a `file://` import out of the store resolves
      # those bare specifiers against *this* output's node_modules -- opencode's
      # own ~/.config/opencode/node_modules is never on that lookup path. A
      # production-only install would be much smaller but drops packages that
      # upstream lists under devDependencies while still importing them from the
      # bundles (zod, @opentui/core), so it would break the TUI plugin. Trimming
      # this further means narrowing the --external sets below and verifying
      # plugin load and TUI rendering against a real opencode session.
      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        for path in ${pkgs.lib.escapeShellArgs runtimeFiles}; do
          [ -e "$path" ] || continue
          mkdir -p "$out/$(dirname "$path")"
          cp -R "$path" "$out/$path"
        done
        cp package.json "$out/package.json"
        cp -R node_modules "$out/node_modules"
        runHook postInstall
      '';
    };
  ohMyOpenCodeSlimPackage = mkBunPluginPackage {
    pname = "oh-my-opencode-slim";
    source = inputs.oh-my-opencode-slim;
    buildCommands = ''
      bun build src/index.ts src/tui.ts \
        --outdir dist \
        --target node \
        --format esm \
        --external @opencode-ai/plugin \
        --external @opencode-ai/plugin/tui \
        --external @opencode-ai/sdk \
        --external @opencode-ai/sdk/v2 \
        --external @opentui/core \
        --external @opentui/solid \
        --external jsdom \
        --external zod
    '';
  };
  ohMyOpenCodeSlimServerWrapper = pkgs.writeText "oh-my-opencode-slim.js" ''
    import server from "file://${ohMyOpenCodeSlimPackage}/dist/index.js";

    export default {
      id: "oh-my-opencode-slim:server",
      server,
    };
  '';
  ohMyOpenCodeSlimTuiPluginSpec = "file://${ohMyOpenCodeSlimPackage}/dist/tui.js";
  # The upstream publish workflow does not write npm versions back to
  # package.json. Load the flake-locked source directly instead of pinning a
  # stale package.json version. Update with:
  # nix flake update opencode-goal-plugin
  goalPluginPackage = mkBunPluginPackage {
    pname = "opencode-goal-plugin";
    source = inputs.opencode-goal-plugin;
  };
  goalServerWrapper = pkgs.writeText "opencode-goal-plugin.js" ''
    import goalModule from "file://${goalPluginPackage}/dist/server.js";

    const options = {
      auto_continue: true,
      defer_while_tasks_active: true,
      max_auto_turns: 50,
      default_token_budget: 400000,
      max_goal_duration_seconds: 10800,
      max_no_progress_turns: 3,
    };

    export const GoalPlugin = (context) => goalModule.server(context, options);
  '';
  goalTuiPluginSpec = "file://${goalPluginPackage}/src/tui.ts";
  # Shared with Claude and Codex. Host-local additions still go in
  # ~/.config/opencode/AGENTS.md, which opencode loads on its own.
  sharedAgentInstructions = import ./agent-instructions { inherit lib pkgs; };
  jsonFormat = pkgs.formats.json { };
  # opencode's permission rules are order-sensitive, and a plain Nix attribute
  # set has no order to give them -- see the comment on permission.bash below.
  orderedJsonFormat = lib.hm.generators.mkDAGOrderedJsonFormat { inherit pkgs jsonFormat; };
in
{
  programs.opencode = {
    enable = true;
    tui.plugin = [
      ohMyOpenCodeSlimTuiPluginSpec
      goalTuiPluginSpec
    ];
  };

  home.sessionVariables.OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS = "true";

  xdg.configFile = {
    "opencode/opencode.jsonc" = {
      force = true;
      source = orderedJsonFormat.generate "opencode.jsonc" {
        "$schema" = "https://opencode.ai/config.json";
        plugin = [ ];
        instructions = [ "${sharedAgentInstructions.file}" ];

        # opencode resolves bash permissions with findLast: the LAST matching
        # rule wins, and a more specific pattern carries no extra weight
        # (packages/opencode/src/permission/index.ts). Nix attribute sets are
        # unordered, so with a plain attrset the emitted order is the key sort
        # and the denies only landed last by ASCII accident -- adding a rule
        # that sorts after them would silently have overridden them. Render
        # through the DAG-ordered format and pin each deny after the rule it
        # exists to override.
        #
        # The denies cover the dangerous spellings we know of. Anything they
        # miss (an unusual flag position, say) still falls through to the
        # surrounding "ask" -- never to "allow".
        permission.bash = {
          "*" = "ask";

          "gh pr checks *" = "allow";
          "gh pr view *" = "allow";
          "gh run list *" = "allow";
          "gh run view *" = "allow";
          "gh run watch *" = "allow";
          "git status *" = "allow";
          "git diff *" = "allow";
          "git log *" = "allow";
          "git rev-parse *" = "allow";

          "git push *" = "ask";
          "gh run rerun *" = "ask";
          "gh workflow run *" = "ask";

          "gh pr merge *" = lib.hm.dag.entryAfter [ "*" ] "deny";
          "git push --force*" = lib.hm.dag.entryAfter [ "git push *" ] "deny";
          "git push -f*" = lib.hm.dag.entryAfter [ "git push *" ] "deny";
          # Same force pushes with the flag after the remote/refspec, plus the
          # `+refspec` spelling, which the flag patterns above never see.
          "git push * --force*" = lib.hm.dag.entryAfter [ "git push *" ] "deny";
          "git push * -f*" = lib.hm.dag.entryAfter [ "git push *" ] "deny";
          "git push * +*" = lib.hm.dag.entryAfter [ "git push *" ] "deny";
        };
        agent = {
          explore.disable = true;
          general.disable = true;
        };
        lsp = true;
      };
    };

    "opencode/oh-my-opencode-slim.json".source = jsonFormat.generate "oh-my-opencode-slim.json" {
      "$schema" =
        "https://unpkg.com/oh-my-opencode-slim@${ohMyOpenCodeSlimVersion}/oh-my-opencode-slim.schema.json";
      autoUpdate = false;
      preset = "openai";
      presets.openai = {
        orchestrator = {
          model = "openai/gpt-5.6-terra-fast";
          variant = "xhigh";
          skills = [ "*" ];
          mcps = [
            "*"
            "!context7"
          ];
        };
        oracle = {
          model = "openai/gpt-5.6-sol";
          variant = "max";
          # oracle owns the review lane; verification-planning is the
          # evidence-path methodology that lane needs.
          skills = [
            "simplify"
            "verification-planning"
          ];
          mcps = [ ];
        };
        librarian = {
          model = "openai/gpt-5.6-luna-fast";
          variant = "low";
          skills = [ ];
          mcps = [
            "context7"
            "gh_grep"
          ];
        };
        explorer = {
          model = "openai/gpt-5.6-luna-fast";
          variant = "low";
          skills = [ ];
          mcps = [ ];
        };
        designer = {
          model = "openai/gpt-5.6-sol";
          variant = "medium";
          skills = [ ];
          mcps = [ ];
        };
        fixer = {
          model = "openai/gpt-5.6-luna-fast";
          variant = "max";
          skills = [ ];
          mcps = [ ];
        };
      };
    };

    "opencode/plugins/oh-my-opencode-slim.js".source = ohMyOpenCodeSlimServerWrapper;
    "opencode/plugins/opencode-goal-plugin.js".source = goalServerWrapper;
  };
}
