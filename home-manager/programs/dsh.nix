{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  package = inputs.deepseek-harness-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  profileDir = "${config.home.homeDirectory}/.dsh/profiles/web";
  workspaceDefaults = pkgs.writeText "dsh-web-workspace.yaml" ''
    packages:
      - .
    nodeLinker: hoisted
    autoInstallPeers: false
  '';
  manifest = {
    name = "dsh-profile-web";
    private = true;
    dependencies = {
      "@deepseek-ai/dsh-subagent-claude-code" = package.version;
      "@deepseek-ai/dsh-subagent-codex" = package.version;
      "@mars-sea/dsh-commandcode-provider" = "0.15.5";
    };
    dsh.profile.bundles = [
      "@deepseek-ai/dsh-base"
      "@deepseek-ai/dsh-web-app"
      "@mars-sea/dsh-commandcode-provider"
      "@deepseek-ai/dsh-experimental-auto-review"
      "@deepseek-ai/dsh-experimental-agent-team-profile"
      "@deepseek-ai/dsh-experimental-inspector-profile"
      "@deepseek-ai/dsh-experimental-tool-worktree"
      "@deepseek-ai/dsh-experimental-session-titles-bundle"
      "@deepseek-ai/dsh-experimental-terminal-bundle"
      "@deepseek-ai/dsh-experimental-session-search"
      "@deepseek-ai/dsh-experimental-ralph-bundle"
      "@deepseek-ai/dsh-experimental-plugin-market-bundle"
      "@deepseek-ai/dsh-subagent-codex"
      "@deepseek-ai/dsh-subagent-claude-code"
    ];
  };
  preferences = [
    {
      id = "locale";
      name = "@deepseek-ai/dsh-client-locale";
      config.preference = "zh";
    }
    {
      id = "session-log-deepseek";
      name = "@deepseek-ai/dsh-session-log-deepseek";
      config.enabled = false;
    }
    {
      id = "ui-chat";
      name = "@deepseek-ai/dsh-client-ui-chat";
      config.transcriptView = "standard";
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
      id = "plugin-market";
      name = "@deepseek-ai/dsh-plugin-market";
      config.indexes = [ "https://cdn.jsdelivr.net/npm/dsh-plugin-catalog/index.json" ];
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
in
{
  home.packages = [
    package
    pkgs.pnpm
  ];

  # Keep the manifest writable for the plugin manager. Local bundles follow the
  # shared layers so their overrides survive; package installation stays explicit.
  home.activation.dshProfile = lib.hm.dag.entryAfter [ "linkGeneration" ] (
    lib.hm.generators.mkImpureConfigMerger {
      inherit pkgs;
      format = "json";
      empty = "{}";
      mode = "600";
      path = "${profileDir}/package.json";
      staticSettings = pkgs.writeText "dsh-web-package.json" (builtins.toJSON manifest);
      jqOperation = ''
        {dsh: {profile: {patchReload: "live"}}} * $dynamic * $static
        | .dsh.profile.bundles = (
            $static.dsh.profile.bundles
            + (($dynamic.dsh.profile.bundles // []) - $static.dsh.profile.bundles)
          )
      '';
    }
  );

  # Home-level patches outrank the UI's profile edits. Seed the writable profile
  # instead, keeping existing rows intact because Cordis replaces config by id.
  home.activation.dshPreferences = lib.hm.dag.entryAfter [ "dshProfile" ] (
    lib.hm.generators.mkImpureConfigMerger {
      inherit pkgs;
      format = "yaml";
      empty = "[]";
      mode = "600";
      path = "${profileDir}/cordis.patch.yml";
      staticSettings = pkgs.writeText "dsh-web-preferences.json" (builtins.toJSON preferences);
      jqOperation = ''
        reduce $static[] as $preference ($dynamic;
          if any(.[]; .id == $preference.id and (.name == null or .name == $preference.name))
          then . else . + [$preference] end)
      '';
    }
  );

  # A pre-existing manifest skips dsh's initialization. Create its pnpm defaults
  # only when the workspace file is absent; existing files and links belong to dsh.
  home.activation.dshWorkspace = lib.hm.dag.entryAfter [ "dshProfile" ] ''
    if [[ ! -e "${profileDir}/pnpm-workspace.yaml" && ! -L "${profileDir}/pnpm-workspace.yaml" ]]; then
      (
        umask 077
        run ${pkgs.coreutils}/bin/cp --no-target-directory --update=none --no-preserve=mode \
          ${workspaceDefaults} "${profileDir}/pnpm-workspace.yaml"
      )
    fi
  '';
}
