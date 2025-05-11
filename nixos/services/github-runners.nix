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
      proxy = "http://127.0.0.1:10809";
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
      extraEnvironment = lib.mkIf (thisHostCfg ? proxy) {
        all_proxy = thisHostCfg.proxy;
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
