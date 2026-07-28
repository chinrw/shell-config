{
  lib,
  pkgs,
  ...
}:

# Caddy in front of the two stocks stacks, so they are reachable on the LAN and
# the tailnet while the servers themselves stay on loopback.
#
# No authentication: anything that can reach those addresses can drive the API,
# which has none of its own.
let
  endpoints = import ../../lib/stocks-endpoints.nix;

  # Binding the addresses one by one rather than a wildcard: the servers hold
  # 127.0.0.1:<port> on these same ports.
  siteFor = port: ''
    ${lib.concatStringsSep " " (endpoints.originsFor port)} {
      bind ${lib.concatStringsSep " " endpoints.addresses}
      reverse_proxy 127.0.0.1:${toString port}
    }
  '';

  # Host reaches the server unchanged, which is what STOCKS_ALLOWED_ORIGINS in
  # stocks-server.nix matches on. `admin off` means no `caddy reload`; restart
  # the unit instead.
  rawCaddyfile = pkgs.writeText "stocks-proxy.caddyfile.in" ''
    {
      admin off
      log {
        level ERROR
      }
    }

    ${lib.concatMapStringsSep "\n" siteFor (builtins.attrValues endpoints.ports)}
  '';

  # Only to stop the adapter warning about indentation on every start.
  caddyfile = pkgs.runCommand "stocks-proxy.caddyfile" { } ''
    cp ${rawCaddyfile} "$out"
    chmod +w "$out"
    ${lib.getExe pkgs.caddy} fmt --overwrite "$out"
  '';
in
{
  systemd.user.services.stocks-proxy = {
    Unit = {
      Description = "Caddy front for the stocks stacks (LAN + tailnet)";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.caddy} run --adapter caddyfile --config ${caddyfile}";
      # Matches what the NixOS module sets; caddy never needs to gain
      # privileges here, both ports are above 1024.
      NoNewPrivileges = true;
      # tailscaled assigns the tailnet addresses some time after boot, and a
      # bind that arrives first exits 1. Retrying is the recovery path.
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
