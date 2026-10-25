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
    ../services/tailscale-exit-proxy.nix
    ./proxy.nix
    ./web.nix
    ./postgresql.nix
    ./openlist.nix
    ./kikoeru-neo.nix
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
  sops.defaultSopsFile = ../../secrets/hosts/media-lxc.yaml;

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
  # while the other router is offline. The exit node pairs with vm-nix's and
  # sends client traffic through the xray in proxy.nix. Tailscale refuses to
  # relay the exit node's ::/0 unless IPv6 forwarding stays on.
  services.tailscale = {
    useRoutingFeatures = "both";
    extraSetFlags = [
      "--ssh=false"
      "--advertise-routes=192.168.0.0/24"
      "--advertise-exit-node"
    ];
  };

  systemd.services.docker.unitConfig.ConditionPathIsMountPoint = lib.mkForce [ ];

  # AdGuard on this host serves the home.midashood.top rewrites.
  networking.nameservers = [ "127.0.0.1" ];
}
