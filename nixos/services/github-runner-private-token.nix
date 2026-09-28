{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  upstream = import (modulesPath + "/services/continuous-integration/github-runner/service.nix") {
    inherit config lib pkgs;
  };
  protectToken =
    command:
    let
      parts = lib.splitString " " command;
      script = builtins.head parts;
      patched = pkgs.runCommand "github-runner-configure-private-token" { } ''
        substitute ${script} "$out" \
          --replace-fail 'args+=(--token "$token")' 'export ACTIONS_RUNNER_INPUT_TOKEN="$token"' \
          --replace-fail 'args+=(--pat "$token")' 'export ACTIONS_RUNNER_INPUT_PAT="$token"'
        chmod 0555 "$out"
      '';
    in
    if lib.hasInfix "-configure.sh" script then
      "${patched} ${lib.concatStringsSep " " (builtins.tail parts)}"
    else
      command;
  enabledRunners = lib.filterAttrs (_: runner: runner.enable) config.services.github-runners;
in
{
  systemd.services = lib.mapAttrs' (
    name: _:
    let
      original =
        (builtins.head upstream.config.systemd.services."github-runner-${name}".serviceConfig.contents)
        .ExecStartPre;
    in
    lib.nameValuePair "github-runner-${name}" {
      # The upstream configure script passes credentials in argv, visible in process listings.
      serviceConfig.ExecStartPre = lib.mkForce (map protectToken original);
    }
  ) enabledRunners;
}
