{
  lib,
  pkgs,
  username,
  ...
}:
{
  imports = [
    ../proxmox-lxc.nix
    ./updater.nix
    ./runners.nix
  ];

  sops.age.keyFile = "/home/${username}/.config/sops/age/keys.txt";

  services.tailscale.extraSetFlags = [ "--ssh=false" ];

  systemd.services.docker.unitConfig.ConditionPathIsMountPoint = lib.mkForce [ ];

  # Bound daemon builds and updater evaluation together, leaving room for node services.
  systemd.slices.nix-build.sliceConfig = {
    MemoryHigh = "5G";
    MemoryMax = "6G";
    MemorySwapMax = "24G";
  };
  systemd.services.nix-daemon.serviceConfig.Slice = "nix-build.slice";
  systemd.services.shell-config-updater.serviceConfig.Slice = "nix-build.slice";

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
