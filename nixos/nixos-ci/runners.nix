{
  config,
  lib,
  pkgs,
  ...
}:
let
  waitForUpdater = pkgs.writeShellScript "wait-for-config-updater" ''
    set -eu
    while :; do
      state=$(${pkgs.systemd}/bin/systemctl show shell-config-updater.service -p ActiveState --value)
      case "$state" in
        active|activating|deactivating) ${pkgs.coreutils}/bin/sleep 5 ;;
        *) break ;;
      esac
    done
  '';
  runners = {
    rex = {
      name = "rex-nixos-ci";
      url = "https://github.com/rex-rs/rex";
    };
  };
in
{
  imports = [ ../services/github-runner-private-token.nix ];

  systemd.tmpfiles.rules = lib.concatLists (
    lib.mapAttrsToList (name: _: [
      "d /work/${name}-runner 0700 ci ci -"
      "d /cache/${name}-runner 0700 ci ci -"
    ]) runners
  );

  services.github-runners = lib.mapAttrs (name: runner: {
    enable = true;
    inherit (runner) name url;
    user = "ci";
    group = "ci";
    tokenFile = "/var/lib/ci-secrets/${name}-registration-token";
    tokenType = "registration";
    replace = true;
    nodeRuntimes = [ "node24" ];
    workDir = "/work/${name}-runner";
    extraLabels = [
      "nixos-ci-canary"
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
      http_proxy = config.networking.proxy.default;
      https_proxy = config.networking.proxy.default;
      no_proxy = config.networking.proxy.noProxy;
      NO_PROXY = config.networking.proxy.noProxy;
      XDG_CACHE_HOME = "/cache/${name}-runner";
      CARGO_BUILD_JOBS = "4";
      ACTIONS_RUNNER_HOOK_JOB_STARTED = "${waitForUpdater}";
    };
    serviceOverrides = {
      BindPaths = [ "/dev/kvm" ];
      DeviceAllow = [ "/dev/kvm rw" ];
      ReadWritePaths = [ "/cache/${name}-runner" ];
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
  }) runners;

  systemd.services =
    (lib.mapAttrs' (
      name: _:
      lib.nameValuePair "github-runner-${name}" {
        wants = [ "docker.service" ];
        after = [ "docker.service" ];
        unitConfig.RequiresMountsFor = [
          "/cache"
          "/work"
        ];
      }
    ) runners)
    // {

      # The activating state is visible before this check. New workers wait in their start hook.
      shell-config-updater.serviceConfig.ExecCondition = pkgs.writeShellScript "skip-updater-while-ci-busy" ''
        if ${pkgs.procps}/bin/pgrep -u ci -f '(^|/)\.?Runner\.Worker(-wrapped)?([[:space:]]|$)' >/dev/null; then
          exit 1
        fi
      '';
    };
}
