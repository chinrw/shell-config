{
  config,
  lib,
  pkgs,
  hostname,
  ...
}:
let
  sharedAgentInstructions = import ./agent-instructions { inherit lib pkgs; };
in
{
  # Point Antigravity CLI's global skill manifest at the shared ~/.agents/skills
  # directory so it discovers the same skills without duplicating symlinks.
  home.file.".gemini/config/skills.json".text = builtins.toJSON {
    entries = [
      {
        path = "${config.home.homeDirectory}/.agents/skills";
      }
    ];
  };

  home.activation.antigravityAgentsMd = sharedAgentInstructions.mkActivation {
    inherit hostname;
    homeDirectory = config.home.homeDirectory;
    tool = "Antigravity";
    directory = "${config.home.homeDirectory}/.gemini/config";
    source = "shell-config/home-manager/programs/antigravity.nix";
  };
}
