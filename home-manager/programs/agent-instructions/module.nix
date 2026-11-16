{
  config,
  lib,
  pkgs,
  hostname,
  ...
}:
let
  instructions = import ./. { inherit lib pkgs; };
in
{
  home.activation.sharedAgentInstructions = lib.hm.dag.entryAfter [ "writeBoundary" ] (
    instructions.assemble {
      inherit hostname;
      homeDirectory = config.home.homeDirectory;
      tool = "Shared";
      directory = "${config.home.homeDirectory}/.agents";
      sharedFile = instructions.file;
      heading = "# User-scope Agent Instructions";
    }
  );
}
