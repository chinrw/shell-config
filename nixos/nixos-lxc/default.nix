{ lib, ... }:
{
  # A work host for agents. It runs no shared services, so rebooting it or
  # running it out of memory affects nothing else.
  imports = [ ../proxmox-lxc.nix ];

  # One of the subnet routers for the home LAN, so tailnet clients keep a way
  # in while another router is offline.
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

  # The Nix sandbox drops supplementary groups, so kvm membership never
  # reaches a VM test and qemu falls back to TCG. The build users' primary
  # group gets an ACL instead, keeping the node 0660 for everyone else.
  systemd.tmpfiles.rules = [ "a+ /dev/kvm - - - - g:nixbld:rw" ];

  networking.nameservers = [ "192.168.0.1" ];
  networking.proxy = {
    default = "http://192.168.0.241:10809";
    noProxy = (import ../../lib/proxy.nix).noProxy;
  };
}
