{ config, pkgs, ... }:

let
  lanIf = "enp6s18";   # faces your local network – clients use this as GW
  wanIf = "enp6s18";   # faces the Internet
in
{
  # ── Kernel routing ───────────────────────────────────────────────────
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    # "net.ipv6.conf.all.forwarding" = true;   # keep if you serve v6
  };
  # ── SOCKS bridge ─────────────────────────────────────────────────────
  services.redsocks.enable = true;
  services.redsocks.redsocks = [{
    ip   = "0.0.0.0";
    port = 12346;              # local port redsocks binds to
    type = "socks5";
    proxy = "127.0.0.1:10808"; # your existing SOCKS5 daemon
    redirectCondition = true;
    doNotRedirect = [
      "-d 0.0.0.0/8" "-d 10.0.0.0/8" "-d 127.0.0.0/8"
      "-d 169.254.0.0/16" "-d 172.16.0.0/12" "-d 192.168.0.0/16"
      "-d ::1/128" "-d fc00::/7" "-d fe80::/10"
    ];
  }];

    networking.nftables.enable  = true;

  networking.nftables.tables = {

    # === IPv4 NAT table =================================================
    nat4 = {
      family  = "ip";
      content = ''
        table ip nat4 {

          chain prerouting {
            type nat hook prerouting priority dstnat; policy accept;

            # only packets *from* the LAN interface enter here
            iifname "${lanIf}" ip daddr {
              0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8,
              169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16,
              224.0.0.0/4, 240.0.0.0/4
            } return

            iifname "${lanIf}" tcp redirect to :12346
          }

          chain output {
            type nat hook output priority -100; policy accept;

            # exempt local / RFC-1918 for traffic generated *by this host*
            ip daddr {
              0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8,
              169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16,
              224.0.0.0/4, 240.0.0.0/4
            } return

            tcp redirect to :12346
          }

          chain postrouting {
            type nat hook postrouting priority srcnat; policy accept;
            oifname "${wanIf}" masquerade
          }
        }
      '';
    };


}
