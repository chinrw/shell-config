{ config, pkgs, ... }:
{
  imports = [ ../services/github-runner-private-token.nix ];

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
    "a+ /work - - - - u:ci:r-x"
    "a+ /cache - - - - u:ci:r-x"
    "d /work/rex-runner 0700 ci ci -"
    "d /cache/rex-runner 0700 ci ci -"
  ];
  services.github-runners.rex = {
    enable = true;
    name = "Constantinople-nixos-lxc";
    url = "https://github.com/rex-rs/rex";
    tokenFile = "/var/lib/ci-secrets/rex-registration-token";
    tokenType = "registration";
    user = "ci";
    group = "ci";
    workDir = "/work/rex-runner";
    extraLabels = [
      "nix"
      "nixos"
      "docker"
      "kvm"
      "trusted"
    ];
    extraPackages = with pkgs; [
      docker
      python3
      qemu
    ];
    extraEnvironment = {
      http_proxy = "http://127.0.0.1:10809";
      https_proxy = "http://127.0.0.1:10809";
      no_proxy = config.networking.proxy.noProxy;
      NO_PROXY = config.networking.proxy.noProxy;
      XDG_CACHE_HOME = "/cache/rex-runner";
    };
    serviceOverrides = {
      BindPaths = [ "/dev/kvm" ];
      DeviceAllow = [ "/dev/kvm rw" ];
      ReadWritePaths = [ "/cache/rex-runner" ];
      PrivateUsers = false;
      RestrictNamespaces = "user mnt pid ipc net";
      SystemCallFilter = [
        "@system-service"
        "unshare"
        "setns"
        "clone"
        "clone3"
        "pkey_alloc"
        "pkey_free"
        "pkey_mprotect"
        "mount"
        "umount2"
        "pivot_root"
      ];
    };
  };
  systemd.services.github-runner-rex = {
    wants = [
      "docker.service"
      "xray.service"
    ];
    after = [
      "docker.service"
      "xray.service"
    ];
    unitConfig.RequiresMountsFor = [
      "/work"
      "/cache"
    ];
  };
}
