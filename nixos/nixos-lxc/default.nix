{ lib, ... }:
{
  imports = [
    ../proxmox-lxc.nix
    ./proxy.nix
    ./web.nix
    ./postgresql.nix
    ./applications.nix
    ./lanraragi.nix
    ./runner.nix
  ];

  systemd.services.docker.unitConfig.ConditionPathIsMountPoint = lib.mkForce [ ];

  networking.nameservers = [ "127.0.0.1" ];

  # A second subnet router for the home LAN, so tailnet clients keep a way in
  # while the other router is offline.
  services.tailscale = {
    useRoutingFeatures = "both";
    extraSetFlags = [ "--advertise-routes=192.168.0.0/24" ];
  };

  # The advertised route is IPv4 only, so the IPv6 forwarding that "both"
  # turns on serves nothing here. mkForce because the tailscale module sets it
  # with mkOverride 97, which outranks a plain definition.
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = lib.mkForce false;
}
