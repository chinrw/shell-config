{
  config,
  pkgs,
  lib,
  ...
}:
let
  xrayTproxyPort = 12345;
  fwMark = 1;
  routeTable = 100;
  tsIface = "tailscale0";
in
{
  networking.firewall.trustedInterfaces = [ tsIface ];

  networking.firewall.extraCommands = ''
    ip -4 rule add fwmark ${toString fwMark} lookup ${toString routeTable} 2>/dev/null || true
    ip -4 route replace local 0.0.0.0/0 dev lo table ${toString routeTable}

    iptables -t mangle -N TS_TPROXY 2>/dev/null || iptables -t mangle -F TS_TPROXY

    iptables -t mangle -A TS_TPROXY -d 0.0.0.0/8       -j RETURN
    iptables -t mangle -A TS_TPROXY -d 10.0.0.0/8      -j RETURN
    iptables -t mangle -A TS_TPROXY -d 100.64.0.0/10   -j RETURN
    iptables -t mangle -A TS_TPROXY -d 127.0.0.0/8     -j RETURN
    iptables -t mangle -A TS_TPROXY -d 169.254.0.0/16  -j RETURN
    iptables -t mangle -A TS_TPROXY -d 172.16.0.0/12   -j RETURN
    iptables -t mangle -A TS_TPROXY -d 192.168.0.0/16  -j RETURN
    iptables -t mangle -A TS_TPROXY -d 224.0.0.0/4     -j RETURN
    iptables -t mangle -A TS_TPROXY -d 240.0.0.0/4     -j RETURN

    iptables -t mangle -A TS_TPROXY -p tcp -j TPROXY --on-port ${toString xrayTproxyPort} --on-ip 127.0.0.1 --tproxy-mark ${toString fwMark}
    iptables -t mangle -A TS_TPROXY -p udp -j TPROXY --on-port ${toString xrayTproxyPort} --on-ip 127.0.0.1 --tproxy-mark ${toString fwMark}

    iptables -t mangle -D PREROUTING -i ${tsIface} -j TS_TPROXY 2>/dev/null || true
    iptables -t mangle -A PREROUTING -i ${tsIface} -j TS_TPROXY
  '';

  networking.firewall.extraStopCommands = ''
    iptables -t mangle -D PREROUTING -i ${tsIface} -j TS_TPROXY 2>/dev/null || true
    iptables -t mangle -F TS_TPROXY 2>/dev/null || true
    iptables -t mangle -X TS_TPROXY 2>/dev/null || true
    ip -4 rule del fwmark ${toString fwMark} lookup ${toString routeTable} 2>/dev/null || true
    ip -4 route del local 0.0.0.0/0 dev lo table ${toString routeTable} 2>/dev/null || true
  '';
}
