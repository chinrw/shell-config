{ config, lib, pkgs, modulesPath, ... }:
let
  upstream = import (modulesPath + "/services/continuous-integration/github-runner/service.nix") {
    inherit config lib pkgs;
  };
  original = (builtins.head upstream.config.systemd.services.github-runner-rex.serviceConfig.contents).ExecStartPre;
  protectToken = command:
    let
      parts = lib.splitString " " command;
      script = builtins.head parts;
      patched = pkgs.runCommand "github-runner-configure-private-token" { } ''
        substitute ${script} "$out" \
          --replace-fail 'args+=(--token "$token")' 'export ACTIONS_RUNNER_INPUT_TOKEN="$token"' \
          --replace-fail 'args+=(--pat "$token")' 'export ACTIONS_RUNNER_INPUT_PAT="$token"'
        chmod 0555 "$out"
      '';
    in
    if lib.hasInfix "-configure.sh" script then
      "${patched} ${lib.concatStringsSep " " (builtins.tail parts)}"
    else command;
in
{
  users.groups.ci.gid = 1001;
  users.users.ci = {
    isSystemUser = true;
    uid = 1001;
    group = "ci";
    extraGroups = [ "docker" "kvm" ];
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
    extraLabels = [ "nix" "nixos" "docker" "kvm" "trusted" ];
    extraPackages = with pkgs; [ docker python3 qemu ];
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
        "@system-service" "unshare" "setns" "clone" "clone3"
        "pkey_alloc" "pkey_free" "pkey_mprotect" "mount" "umount2" "pivot_root"
      ];
    };
  };
  systemd.services.github-runner-rex = {
    wants = [ "docker.service" "xray.service" ];
    after = [ "docker.service" "xray.service" ];
    unitConfig.RequiresMountsFor = [ "/work" "/cache" ];
    # The upstream configure script passes credentials in argv, visible in process listings.
    serviceConfig.ExecStartPre = lib.mkForce (map protectToken original);
  };
}
