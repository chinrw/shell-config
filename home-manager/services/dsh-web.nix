{ listenAddress }:
{
  config,
  hostname,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  package = inputs.deepseek-harness-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  systemd.user.services.dsh-web = {
    Unit.Description = "DeepSeek Harness Web";
    Unit.After = [ "sops-nix.service" ];
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStart = "${package}/bin/dsh web --no-open --host ${listenAddress} --port 3081 --public-url http://${listenAddress}:3081/ --trusted-host ${hostname}:3081";
      WorkingDirectory = config.home.homeDirectory;
      # Agent tools need the user's installed programs without an interactive shell.
      Environment = [
        "PATH=${
          lib.concatStringsSep ":" (
            config.home.sessionPath
            ++ [
              "${config.home.profileDirectory}/bin"
              "/run/wrappers/bin"
              "/run/current-system/sw/bin"
            ]
          )
        }"
      ];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
