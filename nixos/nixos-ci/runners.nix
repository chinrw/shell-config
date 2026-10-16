{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Each runner takes one job at a time, so parallel kikoeru-neo jobs need
  # one runner each. They keep separate caches so concurrent jobs do not share
  # a working tree.
  kikoeruNeoRunner = suffix: {
    enable = true;
    name = "kikoeru-neo-nixos-ci${suffix}";
    url = "https://github.com/chinrw/kikoeru-neo";
    cacheDir = "/cache/kikoeru-neo-runner${suffix}";
    labels = [ "kikoeru-neo" ];
  };
  # One stocks CI run starts its jobs in parallel, one per runner. All stocks
  # runners share one cache tree, because cargo and uv lock their caches for
  # concurrent use and the e2e job reads tarballs other jobs leave in share/.
  # They also share one registration token file, since a token is per repo.
  stocksRunnerCount = 6;
  stocksRunner = i: {
    enable = true;
    name = "stocks-nixos-ci-${toString i}";
    url = "https://github.com/chinrw/stocks";
    cacheDir = "/cache/stocks-ci";
    tokenName = "stocks";
    stocksCache = true;
    # stocks workflows select runners with [self-hosted, Linux, X64, nix].
    labels = [ "nix" ];
  };
  runners = {
    rex = {
      enable = true;
      name = "rex-nixos-ci";
      url = "https://github.com/rex-rs/rex";
      cacheDir = "/cache/rex-runner";
      labels = [ "nixos-ci-canary" ];
    };
    kikoeru-neo = kikoeruNeoRunner "";
    kikoeru-neo-2 = kikoeruNeoRunner "-2";
    kikoeru-neo-3 = kikoeruNeoRunner "-3";
    asterinas-selfhost = {
      enable = true;
      name = "asterinas-selfhost-nixos-ci";
      url = "https://github.com/chinrw/asterinas";
      cacheDir = "/cache/asterinas-selfhost-runner";
      labels = [
        "asterinas-selfhost"
        "nix"
      ];
      # Its jobs boot QEMU guests with several GiB of RAM. Under memory
      # pressure the kernel should pick this runner before the others.
      oomScoreAdjust = 500;
    };
  }
  // lib.listToAttrs (
    map (i: lib.nameValuePair "stocks-${toString i}" (stocksRunner i)) (lib.range 1 stocksRunnerCount)
  );
  enabledRunners = lib.filterAttrs (_: runner: runner.enable) runners;
  usesStocksCache = runner: runner.stocksCache or false;
in
{
  imports = [ ../services/github-runner-private-token.nix ];

  systemd.tmpfiles.rules =
    lib.concatLists (
      lib.mapAttrsToList (
        name: runner:
        [ "d /work/${name}-runner 0700 ci ci -" ]
        # default.nix already creates the shared stocks cache root.
        ++ lib.optional (!usesStocksCache runner) "d ${runner.cacheDir} 0700 ci ci -"
      ) enabledRunners
    )
    ++ lib.optionals (lib.any usesStocksCache (lib.attrValues enabledRunners)) [
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
    tokenFile = "/var/lib/ci-secrets/${runner.tokenName or name}-registration-token";
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
    }
    // lib.optionalAttrs (usesStocksCache runner) {
      CARGO_HOME = "/var/cache/stocks-ci/cargo";
      UV_CACHE_DIR = "/var/cache/stocks-ci/uv";
      XDG_CACHE_HOME = "/var/cache/stocks-ci/xdg";
      UV_LINK_MODE = "copy";
    };
    serviceOverrides = {
      Restart = lib.mkForce "on-failure";
      RestartSec = "30s";
      BindPaths = [ "/dev/kvm" ];
      DeviceAllow = [ "/dev/kvm rw" ];
      ReadWritePaths = [ runner.cacheDir ];
      InaccessiblePaths = lib.optionals (!usesStocksCache runner) [ "-/cache/stocks-ci" ];
      OOMScoreAdjust = runner.oomScoreAdjust or 0;
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

      # An updater run can rebuild hundreds of packages, so it only starts on an
      # idle machine. Jobs that arrive mid-run proceed anyway, because a runner
      # that waits for the updater can stall CI for hours.
      shell-config-updater.serviceConfig.ExecCondition = pkgs.writeShellScript "skip-updater-while-ci-busy" ''
        if ${pkgs.procps}/bin/pgrep -u ci -f '(^|/)\.?Runner\.Worker(-wrapped)?([[:space:]]|$)' >/dev/null; then
          exit 1
        fi
      '';
    };
}
