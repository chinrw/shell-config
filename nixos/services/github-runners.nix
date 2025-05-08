{ config, pkgs, ... }:
{

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

  services.github-runners = {
    runner1 = {
      enable = true;
      name = "midashood";
      tokenFile = config.sops.secrets."github-runners/midashood".path;
      url = "https://github.com/rex-rs/rex";
      extraLabels = [ "nix" ];
      user = "midashood";
      workDir = "/var/lib/github-runner/midashood";
      replace = true;
      extraEnvironment = {
        all_proxy = "http://10.0.0.242:10809";
      };
    };
  };
}
