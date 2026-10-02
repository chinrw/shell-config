{
  config,
  lib,
  pkgs,
  features,
  ...
}:
let
  enabled = pkgs.stdenv.hostPlatform.isLinux && builtins.elem "chatgpt-linker-tunnel" features;
  tunnelConfig = "${config.xdg.configHome}/tunnel-client";
  linkerLauncher = pkgs.writeShellScript "chatgpt-linker-mcp" ''
    # The evidence process must not inherit the tunnel's credentials.
    exec ${pkgs.coreutils}/bin/env -i HOME="$RUNTIME_DIRECTORY" \
      ${config.programs.chatgpt-linker.package}/bin/chatgpt-linker serve \
      --exchange ${lib.escapeShellArg "${config.xdg.stateHome}/chatgpt-linker/exchange"}
  '';
  tunnelLauncher = pkgs.writeShellScript "chatgpt-linker-tunnel" ''
    exec ${lib.escapeShellArg "${config.home.homeDirectory}/.local/bin/tunnel-client"} run \
      --profile-file ${lib.escapeShellArg "${tunnelConfig}/chatgpt-linker.yaml"} \
      --control-plane.api-key ${lib.escapeShellArg "file:${tunnelConfig}/chatgpt-linker.key"} \
      --mcp.command 'command=${linkerLauncher},channel=main'
  '';
in
{
  systemd.user.services.chatgpt-linker = lib.mkIf enabled {
    Unit.Description = "ChatGPT Linker tunnel";
    Service = {
      ExecStart = "${tunnelLauncher}";
      Restart = "on-failure";
      RestartSec = 10;
      RuntimeDirectory = "chatgpt-linker";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
