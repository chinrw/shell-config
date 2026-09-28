{ ... }:
{
  imports = [ ../services/shell-config-updater.nix ];

  services.shell-config-updater = {
    githubTokenFile = "/var/lib/ci-secrets/shell-config-updater/github-token";
    cachixConfigFile = "/var/lib/ci-secrets/shell-config-updater/cachix.dhall";
    maxJobs = 1;
    cores = 2;
    publish = true;
  };

}
