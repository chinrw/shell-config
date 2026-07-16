{
  config,
  lib,
  hostname,
  ...
}:
let
  # Single source of truth for the service identity: tmpfiles ownership, the
  # runner units' User=, and the users./groups. definitions below all derive
  # from these two bindings, so a rename cannot silently desync them.
  runnerUser = "midashood";
  runnerGroup = "github-runners";

  # All stocks runners live on one host and run as the same user; cargo and
  # uv both lock their caches for concurrent access, so the six runners share
  # ONE persistent download cache instead of re-filling six ephemeral HOMEs
  # after every service restart (HOME == workDir, which the runner module
  # wipes on every start). XDG_CACHE_HOME keeps nix's flake eval/tarball
  # caches warm as well (sqlite, concurrency-safe); uv/cargo take their
  # explicit vars regardless. Consumed by stocks .github/workflows/ci.yml,
  # which also keeps its persistent cargo target dirs and the same-host e2e
  # artifact mirror under this tree.
  #
  # /var/cache/stocks-ci MUST be a real host path shared by all units:
  # PrivateTmp=true (module default) makes /tmp and /var/tmp unit-private,
  # so nothing under /var/tmp can ever cross runners. And under
  # ProtectSystem=strict (module default) the tree is read-only inside the
  # sandbox unless a stocks unit gets ReadWritePaths for it. Non-stocks units
  # mask the whole tree with InaccessiblePaths — see mkRunner.
  stocksCacheRoot = "/var/cache/stocks-ci";
  stocksCacheUnitPath = "-${stocksCacheRoot}";
  stocksSharedCacheEnv = {
    CARGO_HOME = "${stocksCacheRoot}/cargo";
    UV_CACHE_DIR = "${stocksCacheRoot}/uv";
    XDG_CACHE_HOME = "${stocksCacheRoot}/xdg";
    # The cache and the checkout .venv sit on the same disk but in different
    # bind mounts of the sandbox (ReadWritePaths vs BindPaths), and link(2)
    # across vfsmounts is EXDEV — uv would warn and fall back to copying on
    # every sync. Declare copy mode explicitly to silence the warning.
    UV_LINK_MODE = "copy";
  };

  # Persistent on-disk work dirs keep six concurrent checkouts + .venv out of
  # the small /run tmpfs (RAM). The module still wipes workDir on every
  # service start ("Always clean workDir"), so cross-restart reuse lives in
  # the shared caches above plus /var/cache/stocks-ci/target — not here.
  #
  # MUST NOT collide with the per-runner StateDirectory
  # (/var/lib/github-runner/<attr name>): that directory holds the runner
  # credentials, and the module's workDir wipe would delete them on every
  # start (attr name == cfg.name for the stocks runners, so the mkRunner
  # default path below WOULD collide — hence a separate subtree).
  runnerWorkRoot = "/var/lib/github-runner-work";
  stocksWorkDir = name: "${runnerWorkRoot}/${name}";

  stocksRunnerNames = map (i: "stocks-${toString i}") (lib.range 1 6);
  isStocksRunner = attrName: builtins.elem attrName stocksRunnerNames;

  # systemd accepts multiple textual spellings of the same path, but the
  # runner module's root-owned startup cleanup operates on the resolved path.
  # Reject aliases such as trailing '/', repeated '/', '.', and '..' so the
  # StateDirectory collision check below is semantic rather than textual.
  isCanonicalAbsolutePath =
    path:
    builtins.isString path
    && lib.hasPrefix "/" path
    && path != "/"
    && lib.all (component: component != "" && component != "." && component != "..") (
      lib.splitString "/" (lib.removePrefix "/" path)
    );

  runnersByHost = {
    # "wsl-mini" = {
    #   proxy = "http://10.0.0.242:10809";
    #   name = "midashood";
    #   tokenSecret = config.sops.secrets."github-runners/midashood".path;
    # };
    "vm-nix" = {
      proxy = "http://192.168.0.240:10809";
      runners = {
        # Keep runner1 stable so the existing rex runner retains its state
        # directory (state lives under the attr name, work under cfg.name —
        # /var/lib/github-runner/{runner1,Constantinople} respectively).
        runner1 = {
          name = "Constantinople";
          url = "https://github.com/rex-rs/rex";
        };
      }
      // lib.genAttrs stocksRunnerNames (name: {
        inherit name;
        tokenSecret = "stocks";
        url = "https://github.com/chinrw/stocks";
        workDir = stocksWorkDir name;
      });
    };
  };

  thisHostCfg = runnersByHost.${hostname} or null;
  thisHostRunners = if thisHostCfg == null then { } else thisHostCfg.runners;
  hostProxy = if thisHostCfg == null then null else thisHostCfg.proxy or null;

  # The workDir the module will actually use for a runner declared here
  # (mirrors mkRunner below: explicit workDir, else the cfg.name default).
  resolvedWorkDir = runnerCfg: runnerCfg.workDir or "/var/lib/github-runner/${runnerCfg.name}";

  mkRunner =
    attrName: runnerCfg:
    let
      tokenSecret = runnerCfg.tokenSecret or runnerCfg.name;
      usesStocksCache = isStocksRunner attrName;
    in
    {
      enable = true;
      nodeRuntimes = [ "node24" ];
      name = runnerCfg.name;
      tokenFile = config.sops.secrets."github-runners/${tokenSecret}".path;
      url = runnerCfg.url;
      extraLabels = [ "nix" ];
      user = runnerUser;
      replace = true;
      workDir = resolvedWorkDir runnerCfg;
      extraEnvironment =
        lib.optionalAttrs (hostProxy != null) {
          all_proxy = hostProxy;
          https_proxy = hostProxy;
          http_proxy = hostProxy;
        }
        // lib.optionalAttrs usesStocksCache stocksSharedCacheEnv;
      # Allow the service to create user namespaces
      serviceOverrides = {
        Slice = "github-runners.slice";
        # Only stocks runners may see and write the shared CI cache. Mask it
        # entirely from Rex and any future non-stocks runner using this module.
        ReadWritePaths = lib.optionals usesStocksCache [ stocksCacheUnitPath ];
        InaccessiblePaths = lib.optionals (!usesStocksCache) [ stocksCacheUnitPath ];
        PrivateUsers = lib.mkForce false;
        # Allow namespaces needed for buildFHSEnv + QEMU networking
        RestrictNamespaces = lib.mkForce "user mnt pid ipc net";
        # Allow syscalls needed for namespace creation
        SystemCallFilter = [
          "@system-service"
          # Capability syscalls for bubblewrap
          "@capabilities"
          # Namespace syscalls for bubblewrap/FHS
          "unshare"
          "setns"
          "clone"
          "clone3"
          # Memory protection keys for Node.js V8
          "pkey_alloc"
          "pkey_free"
          "pkey_mprotect"
          # Mount syscalls for bubblewrap
          "mount"
          "umount2"
          "pivot_root"
        ];
      };
    };

in
{
  assertions = [
    {
      assertion = thisHostCfg != null;
      message = "✗ No GitHub runners configured for host “${hostname}”.";
    }
    {
      # The module wipes workDir as root on every service start. Explicit work
      # dirs therefore live below a dedicated root, use one canonical spelling,
      # and must not resolve to the per-runner StateDirectory.
      assertion = lib.all (
        attrName:
        let
          runnerCfg = thisHostRunners.${attrName};
          explicitWorkDir = runnerCfg.workDir or null;
          workDir = resolvedWorkDir runnerCfg;
        in
        workDir == null
        || (
          isCanonicalAbsolutePath workDir
          && workDir != "/var/lib/github-runner/${attrName}"
          && (explicitWorkDir == null || lib.hasPrefix "${runnerWorkRoot}/" workDir)
        )
      ) (lib.attrNames thisHostRunners);
      message = "✗ Runner workDir must be canonical, differ from StateDirectory, and explicit paths must live below ${runnerWorkRoot}.";
    }
  ];

  services.github-runners = lib.mapAttrs mkRunner thisHostRunners;

  systemd.tmpfiles.rules = [
    # Runner work dirs (checkouts, .venv, HOME) — wiped by the module on
    # service start, kept off the /run tmpfs.
    # Root-owned parents prevent a runner from replacing managed subtrees with
    # symlinks; the writable child directories remain owned by the runner user.
    "d ${runnerWorkRoot} 0755 root root -"
    # Shared persistent CI caches (see stocksSharedCacheEnv above). Download
    # caches are not aged: cargo/uv manage their own contents and disk is
    # plentiful; revisit with an explicit prune if growth ever matters.
    "d ${stocksCacheRoot} 0755 root root -"
    "d ${stocksCacheRoot}/cargo 0755 ${runnerUser} ${runnerGroup} -"
    "d ${stocksCacheRoot}/uv 0755 ${runnerUser} ${runnerGroup} -"
    "d ${stocksCacheRoot}/xdg 0755 ${runnerUser} ${runnerGroup} -"
    # Same-host artifact handoff between producer jobs and e2e (stocks
    # ci.yml). GitHub artifacts (30d retention) are the rerun-safe fallback,
    # so age aggressively — these tarballs are large.
    "d ${stocksCacheRoot}/share 0755 ${runnerUser} ${runnerGroup} 3d"
    # Persistent per-runner cargo target dirs (stocks ci.yml). Age tracks
    # atime/mtime/ctime, so artifacts still being linked against stay put;
    # only genuinely stale outputs are pruned (cargo rebuilds them on miss).
    "d ${stocksCacheRoot}/target 0755 ${runnerUser} ${runnerGroup} 30d"
  ]
  ++ map (name: "d ${stocksWorkDir name} 0700 ${runnerUser} ${runnerGroup} -") stocksRunnerNames;

  systemd.slices.github-runners = {
    description = "GitHub Actions runners resource pool";
    sliceConfig = {
      CPUAccounting = true;
      CPUQuota = "2200%";
      MemoryAccounting = true;
      MemoryHigh = "48G";
      MemoryMax = "56G";
      TasksAccounting = true;
      TasksMax = 16384;
    };
  };

  users.groups.${runnerGroup} = { };

  # Define the GitHub Actions runner service user
  users.users.${runnerUser} = {
    isSystemUser = true;
    description = "GitHub Actions Runner Service User";
    createHome = false;
    group = runnerGroup;
    extraGroups = [ "kvm" ];
    shell = "/run/current-system/sw/bin/nologin";
  };
}
