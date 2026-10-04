# ultraplan only completes on a host whose tunnel ChatGPT can reach, so the
# CLI and its tunnel are enabled together.
{ config, ... }:
{
  sops.secrets."chatgpt-linker/tunnel-api-key" = { };

  programs.chatgpt-linker = {
    enable = true;
    tunnel = {
      enable = true;
      healthPort = 18473;
      tunnelId = "tunnel_6aaca9f6cf7481919f1dea0a634e5173";
      apiKeyFile = config.sops.secrets."chatgpt-linker/tunnel-api-key".path;
    };
  };

  systemd.user.services.chatgpt-linker.Unit.After = [ "sops-nix.service" ];
}
