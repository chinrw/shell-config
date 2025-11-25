{
  config,
  lib,
  pkgs,
  hostname,
  ...
}:
let
  runnersByHost = {
    "wsl-mini" = {
      name = "midashood";
      tokenSecret = config.sops.secrets."github-runners/midashood".path;
      proxy = "http://10.0.0.242:10809";
    };
    "vm-nix" = {
      name = "Constantinople";
      tokenSecret = config.sops.secrets."github-runners/Constantinople".path;
      proxy = "http://192.168.0.240:10809";
    };
  };

  thisHostCfg = runnersByHost.${hostname} or null;

in
{
  assertions = [
    {
      assertion = thisHostCfg ? name;
      message = "✗ No GitHub-runner token configured for host “${hostname}”.";
    }
  ];

  services.github-runners = {
    runner1 = {
      enable = true;
      name = thisHostCfg.name;
      tokenFile = config.sops.secrets."github-runners/${thisHostCfg.name}".path;
      url = "https://github.com/rex-rs/rex";
      extraLabels = [ "nix" ];
      user = "midashood";
      replace = true;
      workDir = "/var/lib/github-runner/${thisHostCfg.name}";
      extraEnvironment = lib.mkIf (thisHostCfg ? proxy) {
        all_proxy = thisHostCfg.proxy;
        https_proxy = thisHostCfg.proxy;
        http_proxy = thisHostCfg.proxy;
      };
      # Allow the service to create user namespaces
      serviceOverrides = {
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
