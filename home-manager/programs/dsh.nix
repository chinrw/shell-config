{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  package = inputs.deepseek-harness-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  workspaceDefaults = pkgs.writeText "dsh-web-workspace.yaml" ''
    packages:
      - .
    nodeLinker: hoisted
    autoInstallPeers: false
  '';
  commonDependencies = {
    "@deepseek-ai/dsh-subagent-claude-code" = package.version;
    "@deepseek-ai/dsh-subagent-codex" = package.version;
    "@mars-sea/dsh-commandcode-provider" = "0.17.0";
  };
  commonBundles = [
    "@deepseek-ai/dsh-base"
    "@mars-sea/dsh-commandcode-provider"
    "@deepseek-ai/dsh-experimental-auto-review"
    "@deepseek-ai/dsh-experimental-agent-team-profile"
    "@deepseek-ai/dsh-experimental-tool-worktree"
    "@deepseek-ai/dsh-experimental-terminal-bundle"
    "@deepseek-ai/dsh-experimental-session-search"
    "@deepseek-ai/dsh-experimental-ralph-bundle"
    "@deepseek-ai/dsh-subagent-codex"
    "@deepseek-ai/dsh-subagent-claude-code"
  ];
  commonPreferences = [
    {
      id = "session-log-deepseek";
      name = "@deepseek-ai/dsh-session-log-deepseek";
      config.enabled = false;
    }
    {
      id = "llm-commandcode";
      name = "@mars-sea/dsh-commandcode-provider";
      config = {
        apiKeyEnv = "COMMANDCODE_API_KEY";
        showSidebarQuota = true;
      };
    }
    {
      id = "web";
      name = "@deepseek-ai/dsh-web";
      config = {
        searchProvider = "commandcode";
        fetchProvider = "http";
      };
    }
  ];
  profiles = {
    web = {
      bundles = commonBundles ++ [
        "@deepseek-ai/dsh-web-app"
        "@deepseek-ai/dsh-experimental-inspector-profile"
        "@deepseek-ai/dsh-experimental-session-titles-bundle"
        "@deepseek-ai/dsh-experimental-plugin-market-bundle"
      ];
      preferences = commonPreferences ++ [
        {
          id = "locale";
          name = "@deepseek-ai/dsh-client-locale";
          config.preference = "zh";
        }
        {
          id = "ui-chat";
          name = "@deepseek-ai/dsh-client-ui-chat";
          config.transcriptView = "standard";
        }
        {
          id = "plugin-market";
          name = "@deepseek-ai/dsh-plugin-market";
          config.indexes = [ "https://cdn.jsdelivr.net/npm/dsh-plugin-catalog/index.json" ];
        }
      ];
    };
    headless = {
      bundles = commonBundles ++ [ "@deepseek-ai/dsh-headless" ];
      # Web presets supply delegation tools; native headless uses the base rows.
      preferences =
        commonPreferences
        ++
          map
            (id: {
              inherit id;
              disabled = false;
            })
            [
              "credentials"
              "authorization"
              "deepseek-account"
              "tool-subagent"
              "tool-subagent-fork"
            ];
    };
  };
  configureProfile =
    name: profile:
    let
      directory = "${config.home.homeDirectory}/.dsh/profiles/${name}";
      manifest = {
        name = "dsh-profile-${name}";
        private = true;
        dependencies = commonDependencies;
        dsh.profile.bundles = profile.bundles;
      };
    in
    lib.hm.generators.mkImpureConfigMerger {
      inherit pkgs;
      format = "json";
      empty = "{}";
      mode = "600";
      path = "${directory}/package.json";
      staticSettings = pkgs.writeText "dsh-${name}-package.json" (builtins.toJSON manifest);
      # Keep local bundles after the shared layers and leave package installs explicit.
      jqOperation =
        lib.optionalString (name == "web") ''
          {dsh: {profile: {patchReload: "live"}}} *
        ''
        + ''
          $dynamic * $static
          | .dsh.profile.bundles = (
              $static.dsh.profile.bundles
              + (($dynamic.dsh.profile.bundles // []) - $static.dsh.profile.bundles)
            )
        '';
    }
    + lib.hm.generators.mkImpureConfigMerger {
      inherit pkgs;
      format = "yaml";
      empty = "[]";
      mode = "600";
      path = "${directory}/cordis.patch.yml";
      staticSettings = pkgs.writeText "dsh-${name}-preferences.json" (
        builtins.toJSON profile.preferences
      );
      # Web edits stay writable; headless applies the required shared configuration.
      jqOperation =
        if name == "web" then
          ''
            reduce $static[] as $row ($dynamic;
              if any(.[]; .id == $row.id and (.name == null or .name == $row.name))
              then . else . + [$row] end)
          ''
        else
          ''
            reduce $static[] as $row ($dynamic;
              if any(.[]; .id == $row.id)
              then map(if .id == $row.id then . * $row else . end)
              else . + [$row] end)
          '';
    }
    + ''
      # A pre-existing manifest skips upstream initialization. Seed only a missing file.
      if [[ ! -e "${directory}/pnpm-workspace.yaml" && ! -L "${directory}/pnpm-workspace.yaml" ]]; then
        (
          umask 077
          run ${pkgs.coreutils}/bin/cp --no-target-directory --update=none --no-preserve=mode \
            ${workspaceDefaults} "${directory}/pnpm-workspace.yaml"
        )
      fi
    '';
in
{
  home.packages = [
    package
    pkgs.pnpm
  ]
  ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.bubblewrap ];

  sops.templates = lib.optionalAttrs (config.sops.secrets ? commandcode-api-key) {
    "dsh.env" = {
      path = "${config.home.homeDirectory}/.dsh/.env";
      content = ''
        COMMANDCODE_API_KEY=${config.sops.placeholder.commandcode-api-key}
      '';
    };
  };

  home.activation.dshProfiles = lib.hm.dag.entryAfter [ "linkGeneration" ] (
    lib.concatStringsSep "\n" (lib.mapAttrsToList configureProfile profiles)
  );
}
