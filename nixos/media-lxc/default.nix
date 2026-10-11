{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  sharedGroup = "users";
in
{
  imports = [
    ../proxmox-lxc.nix
    (import ../services/aria2.nix {
      inherit
        config
        lib
        pkgs
        username
        sharedGroup
        ;
    })
    ../services/qbittorrent.nix
    ./autobangumi.nix
  ];

  sops.age.keyFile = "/home/${username}/.config/sops/age/keys.txt";

  services.tailscale.extraSetFlags = [ "--ssh=false" ];

  systemd.services.docker.unitConfig.ConditionPathIsMountPoint = lib.mkForce [ ];

  networking.nameservers = [ "192.168.0.1" ];
  networking.proxy = {
    default = "http://192.168.0.241:10809";
    noProxy = (import ../../lib/proxy.nix).noProxy;
  };
}
