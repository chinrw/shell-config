{ inputs, pkgs, ... }:
let
  # Update with: nix flake update oh-my-opencode-slim
  pluginVersion =
    (builtins.fromJSON (builtins.readFile "${inputs.oh-my-opencode-slim}/package.json")).version;
  pluginSpec = "oh-my-opencode-slim@${pluginVersion}";
  jsonFormat = pkgs.formats.json { };
in
{
  programs.opencode = {
    enable = true;
    tui.plugin = [ pluginSpec ];
  };

  home.sessionVariables.OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS = "true";

  xdg.configFile = {
    "opencode/opencode.jsonc" = {
      force = true;
      source = jsonFormat.generate "opencode.jsonc" {
        "$schema" = "https://opencode.ai/config.json";
        plugin = [ pluginSpec ];
        agent = {
          explore.disable = true;
          general.disable = true;
        };
        lsp = true;
      };
    };

    "opencode/oh-my-opencode-slim.json".source = jsonFormat.generate "oh-my-opencode-slim.json" {
      "$schema" =
        "https://unpkg.com/oh-my-opencode-slim@${pluginVersion}/oh-my-opencode-slim.schema.json";
      autoUpdate = false;
      preset = "openai";
      presets.openai = {
        orchestrator = {
          model = "openai/gpt-5.6-terra";
          variant = "medium";
          skills = [ "*" ];
          mcps = [
            "*"
            "!context7"
          ];
        };
        oracle = {
          model = "openai/gpt-5.6-sol";
          variant = "max";
          skills = [ "simplify" ];
          mcps = [ ];
        };
        librarian = {
          model = "openai/gpt-5.6-luna";
          variant = "low";
          skills = [ ];
          mcps = [
            "websearch"
            "context7"
            "gh_grep"
          ];
        };
        explorer = {
          model = "openai/gpt-5.6-luna";
          variant = "low";
          skills = [ ];
          mcps = [ ];
        };
        designer = {
          model = "openai/gpt-5.6-luna";
          variant = "medium";
          skills = [ ];
          mcps = [ ];
        };
        fixer = {
          model = "openai/gpt-5.6-luna";
          variant = "high";
          skills = [ ];
          mcps = [ ];
        };
      };
    };
  };
}
