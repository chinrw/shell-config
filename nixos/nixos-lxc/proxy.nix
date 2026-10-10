{ config, pkgs, ... }:
let
  xray = pkgs.xray.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../../patches/xray/9d9eaf3-close-xhttp-body.patch ];
  });
in
{
  imports = [ ../services/adguardhome.nix ];

  sops.age.keyFile = "/home/chin39/.config/sops/age/keys.txt";
  sops.secrets.xray = {
    sopsFile = ../../secrets/xray.conf;
    format = "binary";
    mode = "0400";
    restartUnits = [ "xray.service" ];
  };

  networking.proxy = {
    default = "http://127.0.0.1:10809";
    noProxy = (import ../../lib/proxy.nix).noProxy;
  };

  services.adguardhome = {
    host = "127.0.0.1";
    openFirewall = false;
    settings.dns.bind_hosts = [ "127.0.0.1" "192.168.0.241" ];
  };
  networking.firewall.interfaces.eth0 = {
    # 10809 serves the xray HTTP proxy to LAN hosts, so their egress keeps
    # working while vm-nix, which runs the other proxy, is down.
    allowedTCPPorts = [
      53
      10809
    ];
    allowedUDPPorts = [ 53 ];
  };

  services.resolved.settings.Resolve.MulticastDNS = false;
  systemd.services.adguardhome = {
    wants = [ "dnscrypt-proxy.service" ];
    after = [ "dnscrypt-proxy.service" ];
  };

  services.dnscrypt-proxy.settings = {
    ignore_system_dns = true;
  };
  systemd.services.dnscrypt-proxy = {
    wants = [ "xray.service" ];
    after = [ "xray.service" ];
  };

  services.xray = {
    enable = true;
    package = xray;
    settingsFile = config.sops.secrets.xray.path;
  };
  systemd.services.docker = {
    wants = [ "xray.service" ];
    after = [ "xray.service" ];
  };
  systemd.services.nix-daemon = {
    wants = [ "xray.service" ];
    after = [ "xray.service" ];
  };
}
