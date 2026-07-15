{
  config,
  lib,
  hostname,
  ...
}:
let
  runnersByHost = {
    # "wsl-mini" = {
    #   proxy = "http://10.0.0.242:10809";
    #   name = "midashood";
    #   tokenSecret = config.sops.secrets."github-runners/midashood".path;
    # };
    "vm-nix" = {
      proxy = "http://192.168.0.240:10809";
      runners = {
        # Keep runner1 stable so the existing rex runner retains its state directory.
        runner1 = {
          name = "Constantinople";
          url = "https://github.com/rex-rs/rex";
        };
        stocks-1 = {
          name = "stocks-1";
          tokenSecret = "stocks";
          url = "https://github.com/chinrw/stocks";
          workDir = null;
        };
        stocks-2 = {
          name = "stocks-2";
          tokenSecret = "stocks";
          url = "https://github.com/chinrw/stocks";
          workDir = null;
        };
        stocks-3 = {
          name = "stocks-3";
          tokenSecret = "stocks";
          url = "https://github.com/chinrw/stocks";
          workDir = null;
        };
      };
    };
  };

  thisHostCfg = runnersByHost.${hostname} or null;
  thisHostRunners = if thisHostCfg == null then { } else thisHostCfg.runners;
  hostProxy = if thisHostCfg == null then null else thisHostCfg.proxy or null;

  mkRunner =
    runnerCfg:
    let
      tokenSecret = runnerCfg.tokenSecret or runnerCfg.name;
    in
    {
      enable = true;
      nodeRuntimes = [ "node24" ];
      name = runnerCfg.name;
      tokenFile = config.sops.secrets."github-runners/${tokenSecret}".path;
      url = runnerCfg.url;
      extraLabels = [ "nix" ];
      user = "midashood";
      replace = true;
      workDir = runnerCfg.workDir or "/var/lib/github-runner/${runnerCfg.name}";
      extraEnvironment = lib.optionalAttrs (hostProxy != null) {
        all_proxy = hostProxy;
        https_proxy = hostProxy;
        http_proxy = hostProxy;
      };
      # Allow the service to create user namespaces
      serviceOverrides = {
        Slice = "github-runners.slice";
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
  ];

  services.github-runners = lib.mapAttrs (_: mkRunner) thisHostRunners;

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

  users.groups.github-runners = { };

  # Define the GitHub Actions runner service user
  users.users.midashood = {
    isSystemUser = true;
    description = "GitHub Actions Runner Service User";
    createHome = false;
    group = "github-runners";
    extraGroups = [ "kvm" ];
    shell = "/run/current-system/sw/bin/nologin";
  };
}
