{
  config,
  lib,
  pkgs,
  features,
  ...
}:
{
  programs.chatgpt-linker = {
    enable = true;
    tunnel =
      lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && builtins.elem "chatgpt-linker-tunnel" features)
        {
          enable = true;
          healthPort = 18473;
          tunnelId = "tunnel_6aaca9f6cf7481919f1dea0a634e5173";
          apiKeyFile = "${config.xdg.configHome}/tunnel-client/chatgpt-linker.key";
        };
  };
}
