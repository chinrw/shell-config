{
  config,
  lib,
  pkgs,
  ...
}:
let
  waitForUpdater = pkgs.writeShellScript "wait-for-config-updater.sh" ''
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
      enable = true;
      name = "rex-nixos-ci";
      url = "https://github.com/rex-rs/rex";
      cacheDir = "/cache/rex-runner";
      labels = [ "nixos-ci-canary" ];
    };
    stocks = {
      enable = false;
      name = "stocks-nixos-ci-1";
      url = "https://github.com/chinrw/stocks";
      cacheDir = "/cache/stocks-ci";
      labels = [ "nixos-ci-canary" ];
    };
  };
  enabledRunners = lib.filterAttrs (_: runner: runner.enable) runners;
in
{
  imports = [ ../services/github-runner-private-token.nix ];

  systemd.tmpfiles.rules =
    lib.concatLists (
      lib.mapAttrsToList (name: runner: [
        "d /work/${name}-runner 0700 ci ci -"
        "d ${runner.cacheDir} 0700 ci ci -"
      ]) enabledRunners
    )
    ++ lib.optionals runners.stocks.enable [
      "d /cache/stocks-ci/cargo 0700 ci ci -"
      "d /cache/stocks-ci/uv 0700 ci ci -"
      "d /cache/stocks-ci/xdg 0700 ci ci -"
      "d /cache/stocks-ci/share 0700 ci ci 3d"
      "d /cache/stocks-ci/target 0700 ci ci -"
    ];

  services.github-runners = lib.mapAttrs (name: runner: {
    inherit (runner) enable name url;
    user = "ci";
    group = "ci";
    tokenFile = "/var/lib/ci-secrets/${name}-registration-token";
    tokenType = "registration";
    replace = true;
    nodeRuntimes = [ "node24" ];
    workDir = "/work/${name}-runner";
    extraLabels = runner.labels ++ [
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
      XDG_CACHE_HOME = runner.cacheDir;
      CARGO_BUILD_JOBS = "4";
      ACTIONS_RUNNER_HOOK_JOB_STARTED = "${waitForUpdater}";
    }
    // lib.optionalAttrs (name == "stocks") {
      CARGO_HOME = "/var/cache/stocks-ci/cargo";
      UV_CACHE_DIR = "/var/cache/stocks-ci/uv";
      XDG_CACHE_HOME = "/var/cache/stocks-ci/xdg";
      UV_LINK_MODE = "copy";
    };
    serviceOverrides = {
      BindPaths = [ "/dev/kvm" ];
      DeviceAllow = [ "/dev/kvm rw" ];
      ReadWritePaths = [ runner.cacheDir ];
      InaccessiblePaths = lib.optionals (name != "stocks") [ "-/cache/stocks-ci" ];
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
    ) enabledRunners)
    // {

      # The activating state is visible before this check. New workers wait in their start hook.
      shell-config-updater.serviceConfig.ExecCondition = pkgs.writeShellScript "skip-updater-while-ci-busy" ''
        if ${pkgs.procps}/bin/pgrep -u ci -f '(^|/)\.?Runner\.Worker(-wrapped)?([[:space:]]|$)' >/dev/null; then
          exit 1
        fi
      '';
    };
}
