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
    (import ../services/jellyfin.nix { stateDir = "/var/lib/jellyfin"; })
  ];

  sops.age.keyFile = "/home/${username}/.config/sops/age/keys.txt";

  # The Home Manager rclone mount passes --allow-other, which fusermount
  # refuses unless user_allow_other is set; proxmox-lxc.nix turns it off.
  programs.fuse.userAllowOther = lib.mkForce true;

  # Jellyfin clients reach it through caddy on nixos-lxc; 7359 and 1900 are
  # LAN discovery.
  networking.firewall.allowedTCPPorts = [ 8096 ];
  networking.firewall.allowedUDPPorts = [
    7359
    1900
  ];

  services.tailscale.extraSetFlags = [ "--ssh=false" ];

  systemd.services.docker.unitConfig.ConditionPathIsMountPoint = lib.mkForce [ ];

  networking.nameservers = [ "192.168.0.1" ];
  networking.proxy = {
    default = "http://192.168.0.241:10809";
    noProxy = (import ../../lib/proxy.nix).noProxy;
  };
}
