{ ... }:

# Caddy in front of the two stocks stacks, so they are reachable on the LAN and
# the tailnet while the servers stay on loopback. The Rust front clamps its own
# bind (crates/backend/src/main.rs, `resolve_loopback_host` rewrites 0.0.0.0 to
# 127.0.0.1) and names a proxy as the way out.
#
# No authentication: anything that reaches these addresses can read the
# database and drive the writable endpoints, including analysis runs that spend
# the Claude subscription.
let
  endpoints = import ../../lib/stocks-endpoints.nix;

  vhostFor =
    port:
    let
      origins = endpoints.originsFor port;
    in
    {
      # First origin names the vhost, the rest are aliases. Caddy matches Host
      # against all of them and 404s anything else reaching the socket.
      name = builtins.head origins;
      value = {
        serverAliases = builtins.tail origins;
        listenAddresses = endpoints.addresses;
        # Host passes through untouched: the front matches it against
        # STOCKS_ALLOWED_ORIGINS. Rewriting it to the upstream address (nginx's
        # default) clears that check but then fails the Origin/Host comparison
        # on browser POSTs. SSE needs no directive, caddy stops buffering for
        # text/event-stream on its own.
        extraConfig = "reverse_proxy 127.0.0.1:${toString port}";
      };
    };
in
{
  services.caddy = {
    enable = true;
    virtualHosts = builtins.listToAttrs (map vhostFor (builtins.attrValues endpoints.ports));
  };

  # tailscaled assigns the tailnet addresses some time after boot, and the caddy
  # unit sets RestartPreventExitStatus=1, so a bind that arrives first exits 1
  # and stays down. Binding an address that is not up yet avoids the race.
  boot.kernel.sysctl = {
    "net.ipv4.ip_nonlocal_bind" = 1;
    "net.ipv6.ip_nonlocal_bind" = 1;
  };

  # No firewall change: 5001/5002 are already in allowedTCPPorts and that list
  # covers every interface, tailnet included.
}
