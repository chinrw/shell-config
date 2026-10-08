{ ... }:
{
  imports = [
    ../services/shell-config-updater.nix
    (import ../../lib/failure-email.nix).nixos
  ];

  services.shell-config-updater = {
    githubTokenFile = "/var/lib/ci-secrets/shell-config-updater/github-token";
    cachixConfigFile = "/var/lib/ci-secrets/shell-config-updater/cachix.dhall";
    maxJobs = 1;
    cores = 2;
    publish = true;
  };

  systemd.services.shell-config-updater.onFailure = [ "email-failure@%n.service" ];
}
