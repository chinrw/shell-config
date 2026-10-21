# ultraplan only completes on a host whose tunnel ChatGPT can reach, so the
# CLI and its tunnel are enabled together.
{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:
{
  sops.secrets."chatgpt-linker/tunnel-api-key" = {
    sopsFile = ../../secrets/hosts + "/${hostname}.yaml";
  };

  programs.chatgpt-linker = {
    enable = true;
    tunnel = {
      enable = true;
      healthPort = 18473;
      tunnelId =
        {
          vm-nix = "tunnel_6aaca9f6cf7481919f1dea0a634e5173";
          nixos-lxc = "tunnel_6ad84c86847c8191aae79d611dede23c";
        }
        .${hostname};
      apiKeyFile = config.sops.secrets."chatgpt-linker/tunnel-api-key".path;
    };
  };

  systemd.user.services.chatgpt-linker.Unit.After = [ "sops-nix.service" ];
  home.activation.chatgptLinkerState =
    lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "writeBoundary" ]
      ''
        run ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg "${config.xdg.stateHome}/chatgpt-linker"}
      '';
}
