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
    ./proxy.nix
    ./web.nix
    ./postgresql.nix
    ./openlist.nix
    ./lanraragi.nix
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

  # sops-nix decrypts during activation with nobody to type a passphrase, so
  # this key must have none.
  sops.age.keyFile = "/home/${username}/.config/sops/age/keys.txt";

  # 192.168.0.241 is the home services address: hermes, the strm library,
  # CT101's forwards and every host's proxy setting use it. It follows the
  # services, so the host that held them before can be reused freely.
  environment.etc."systemd/network/eth0.network.d/20-services-address.conf".text = ''
    [Network]
    Address=192.168.0.241/24
  '';

  # The Home Manager rclone mount passes --allow-other, which fusermount
  # refuses unless user_allow_other is set. proxmox-lxc.nix turns it off.
  programs.fuse.userAllowOther = lib.mkForce true;

  # Jellyfin clients use caddy on this host. 8096 stays open for LAN players
  # that connect directly, and 7359 and 1900 are LAN discovery.
  networking.firewall.allowedTCPPorts = [ 8096 ];
  networking.firewall.allowedUDPPorts = [
    7359
    1900
  ];

  # A second subnet router for the home LAN, so tailnet clients keep a way in
  # while the other router is offline.
  services.tailscale = {
    useRoutingFeatures = "both";
    extraSetFlags = [
      "--ssh=false"
      "--advertise-routes=192.168.0.0/24"
    ];
  };

  # The advertised route is IPv4 only, so the IPv6 forwarding that "both"
  # turns on serves nothing here. mkForce because the tailscale module sets it
  # with mkOverride 97, which outranks a plain definition.
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = lib.mkForce false;

  systemd.services.docker.unitConfig.ConditionPathIsMountPoint = lib.mkForce [ ];

  # AdGuard on this host serves the home.midashood.top rewrites.
  networking.nameservers = [ "127.0.0.1" ];
}
