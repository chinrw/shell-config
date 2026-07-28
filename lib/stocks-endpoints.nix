# Where the stocks stacks are reachable from outside their own loopback.
#
# Defined once because three files have to agree. The Rust front
# (crates/backend/src/security.rs, `request_host_is_allowed`) serves a request
# only when its `Host` is loopback or an exact entry in
# `STOCKS_ALLOWED_ORIGINS`, so an address caddy binds but the allowlist omits
# answers 403 without saying which part was wrong.
#
# Consumers:
#   - nixos/services/stocks-proxy.nix       (caddy bind + site addresses)
#   - nixos/services/stocks-server.nix      (STOCKS_ALLOWED_ORIGINS)
#   - nixos/services/stocks-dev-server.nix  (STOCKS_ALLOWED_ORIGINS)
#
# Every address here is static: 192.168.0.240 is this VM's LAN address, and the
# 100.x/fd7a: pair plus the MagicDNS name are its tailnet identity, which
# tailscale keeps stable per node.
let
  # Interfaces caddy binds. No loopback: the servers hold 127.0.0.1:<port>, so
  # caddy has to name its addresses instead of taking a wildcard.
  addresses = [
    "192.168.0.240" # LAN (ens18)
    "100.106.89.118" # tailnet v4
    "fd7a:115c:a1e0::2635:5976" # tailnet v6 — MagicDNS hands out both records
  ];

  # The `Host` values a browser can put on the wire for those addresses. IPv6
  # literals keep their brackets: that is the form the header carries.
  hosts = [
    "192.168.0.240"
    "100.106.89.118"
    "[fd7a:115c:a1e0::2635:5976]"
    "vm-nix.tail33107.ts.net"
  ];

  originsFor = port: map (host: "http://${host}:${toString port}") hosts;
in
{
  inherit addresses hosts originsFor;

  # Listen ports, one per worktree. The launcher resolves the real port from
  # that worktree's own .env (PORT=...); this only has to agree with it.
  ports = {
    stocks = 5001;
    stocks-dev = 5002;
  };

  # The STOCKS_ALLOWED_ORIGINS value for a port. Same list the caddy vhost is
  # built from, so the bind set and the allowlist cannot drift apart.
  allowedOriginsFor = port: builtins.concatStringsSep "," (originsFor port);
}
