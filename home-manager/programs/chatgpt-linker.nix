{
  config,
  lib,
  pkgs,
  features,
  ...
}:
{
  services.chatgpt-linker =
    lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && builtins.elem "chatgpt-linker-tunnel" features)
      {
        enable = true;
        tunnelId = "tunnel_6aaca9f6cf7481919f1dea0a634e5173";
        apiKeyFile = "${config.xdg.configHome}/tunnel-client/chatgpt-linker.key";
      };
}
