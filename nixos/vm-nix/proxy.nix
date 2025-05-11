{ config, pkgs, ... }:
let
  lanIf = "ens18"; # faces your local network – clients use this as GW
  wanIf = "ens18"; # faces the Internet
in
{
  # ── Kernel routing ───────────────────────────────────────────────────
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    # "net.ipv6.conf.all.forwarding" = true;   # keep if you serve v6
  };
  # ── SOCKS bridge ─────────────────────────────────────────────────────
  services.redsocks.enable = true;
  services.redsocks.redsocks = [
    {
      ip = "0.0.0.0";
      port = 12346; # local port redsocks binds to
      type = "socks5";
      proxy = "192.168.0.201:10808"; # your existing SOCKS5 daemon
      redirectCondition = true;
      doNotRedirect = [
        "-d 0.0.0.0/8"
        "-d 10.0.0.0/8"
        "-d 127.0.0.0/8"
        "-d 169.254.0.0/16"
        "-d 172.16.0.0/12"
        "-d 192.168.0.0/16"
        "-d ::1/128"
        "-d fc00::/7"
        "-d fe80::/10"
      ];
    }
  ];

  networking.firewall.trustedInterfaces = [ lanIf ];

  networking.firewall.extraCommands = ''
    # Fresh REDSOCKS chain
    iptables -t nat -N REDSOCKS 2>/dev/null || true
    iptables -t nat -F REDSOCKS

    # Exempt RFC-1918, multicast, loopback (same list as doNotRedirect)
    ip46tables="iptables -t nat"
    $ip46tables -A REDSOCKS -d 0.0.0.0/8      -j RETURN
    $ip46tables -A REDSOCKS -d 10.0.0.0/8     -j RETURN
    $ip46tables -A REDSOCKS -d 127.0.0.0/8    -j RETURN
    $ip46tables -A REDSOCKS -d 169.254.0.0/16 -j RETURN
    $ip46tables -A REDSOCKS -d 172.16.0.0/12  -j RETURN
    $ip46tables -A REDSOCKS -d 192.168.0.0/16 -j RETURN
    $ip46tables -A REDSOCKS -d 224.0.0.0/4    -j RETURN
    $ip46tables -A REDSOCKS -d 240.0.0.0/4    -j RETURN

    # Everything else → redsocks
    $ip46tables -A REDSOCKS -p tcp -j REDIRECT --to-ports 12346

    # Hook chain for LAN-originating packets **before routing**
    iptables -t nat -D PREROUTING -i ${lanIf} -p tcp -j REDSOCKS 2>/dev/null || true
    iptables -t nat -A PREROUTING -i ${lanIf} -p tcp -j REDSOCKS   # :contentReference[oaicite:2]{index=2}

    # …and (optionally) local applications too
    iptables -t nat -D OUTPUT -p tcp -j REDSOCKS 2>/dev/null || true
    iptables -t nat -A OUTPUT -p tcp -j REDSOCKS
  '';

}
