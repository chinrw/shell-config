{ pkgs, ... }:
{
  imports = [
    ../proxmox-lxc.nix
    ./updater.nix
    ./runners.nix
  ];

  services.tailscale.extraSetFlags = [ "--ssh=false" ];

  services.nix-serve = {
    enable = true;
    package = pkgs.nix-serve-ng;
    port = 5000;
    secretKeyFile = "/var/lib/ci-secrets/nix-serve-secret-key";
  };
  nix.settings.secret-key-files = [ "/var/lib/ci-secrets/nix-serve-secret-key" ];
  networking.firewall.allowedTCPPorts = [ 5000 ];

  networking.nameservers = [ "192.168.0.1" ];
  networking.proxy = {
    default = "http://192.168.0.240:10809";
    noProxy = (import ../../lib/proxy.nix).noProxy;
  };

  nix.settings = {
    max-jobs = 1;
    cores = 2;
  };

  users.groups.ci.gid = 1001;
  users.users.ci = {
    isSystemUser = true;
    uid = 1001;
    group = "ci";
    extraGroups = [
      "docker"
      "kvm"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /cache 0700 ci ci -"
    "d /work 0700 ci ci -"
    "d /cache/stocks-ci 0700 ci ci -"
    "L+ /var/cache/stocks-ci - - - - /cache/stocks-ci"
  ];
}
