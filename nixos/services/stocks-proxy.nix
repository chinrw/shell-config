{ ... }:

# Puts the two stocks stacks on the LAN and the tailnet without moving the
# servers off loopback.
#
# The Rust front clamps its own bind to loopback (crates/backend/src/main.rs,
# `resolve_loopback_host` — 0.0.0.0 is silently rewritten to 127.0.0.1) and
# names a proxy in front as the supported way out, with STOCKS_ALLOWED_ORIGINS
# as the matching allowlist. This is that proxy.
#
# There is no authentication in front of it, by choice. The app has none of its
# own either: anything that reaches the LAN address or the tailnet can read the
# database and drive the writable endpoints (runtime settings, AI defaults,
# favorites, push configs), including analysis runs that spend the Claude
# subscription. The tailnet half is at least limited to devices in the tailnet.
let
  endpoints = import ../../lib/stocks-endpoints.nix;

  vhostFor =
    port:
    let
      origins = endpoints.originsFor port;
    in
    {
      # First origin names the vhost, the rest are aliases; caddy matches Host
      # against all of them and 404s anything else that reaches the socket.
      name = builtins.head origins;
      value = {
        serverAliases = builtins.tail origins;
        listenAddresses = endpoints.addresses;
        # Host passes through untouched, which is the point: the front matches
        # it against STOCKS_ALLOWED_ORIGINS. Rewriting it to the upstream
        # address (nginx's default) would clear that check and then fail the
        # Origin/Host comparison on every browser POST instead — a much harder
        # failure to read. SSE needs no directive here: caddy stops buffering
        # on its own for text/event-stream responses.
        extraConfig = "reverse_proxy 127.0.0.1:${toString port}";
      };
    };
in
{
  services.caddy = {
    enable = true;
    virtualHosts = builtins.listToAttrs (map vhostFor (builtins.attrValues endpoints.ports));
  };

  # caddy binds the tailnet addresses, and tailscaled assigns those
  # asynchronously after boot. Losing that race is not self-healing: the caddy
  # unit sets RestartPreventExitStatus=1, and a failed bind exits 1, so it would
  # stay dead until someone looked. Binding a not-yet-present address instead
  # succeeds and starts serving the moment the interface appears.
  boot.kernel.sysctl = {
    "net.ipv4.ip_nonlocal_bind" = 1;
    "net.ipv6.ip_nonlocal_bind" = 1;
  };

  # No firewall change: 5001/5002 are already in allowedTCPPorts
  # (nixos/vm-nix/default.nix) and that list applies to every interface, so the
  # tailnet reaches them too.
}
