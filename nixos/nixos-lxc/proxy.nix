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
    noProxy = "localhost,127.0.0.1,::1,192.168.0.240,192.168.0.0/24,10.0.0.0/8,172.16.0.0/12,100.64.0.0/10,.localdomain";
  };

  services.adguardhome = {
    host = "127.0.0.1";
    openFirewall = false;
    settings.dns.bind_hosts = [ "127.0.0.1" "192.168.0.241" ];
  };
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -i eth0 -s 192.168.0.0/24 -d 192.168.0.241 -p udp --dport 53 -j nixos-fw-accept
    iptables -A nixos-fw -i eth0 -s 192.168.0.0/24 -d 192.168.0.241 -p tcp --dport 53 -j nixos-fw-accept
  '';

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
