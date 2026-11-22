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
  ip = "${pkgs.iproute2}/bin/ip";
  nft = "${pkgs.nftables}/bin/nft";

  networkd = config.systemd.network.enable;

  privateRanges = [
    "0.0.0.0/8"
    "10.0.0.0/8"
    "100.64.0.0/10"
    "127.0.0.0/8"
    "169.254.0.0/16"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "224.0.0.0/4"
    "240.0.0.0/4"
  ];

  rulesetFile = pkgs.writeText "ts-tproxy.nft" ''
    table ip ts_tproxy {
      chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname != "${tsIface}" counter return
        ip daddr { ${lib.concatStringsSep ", " privateRanges} } counter return
        meta l4proto { tcp, udp } counter meta mark set ${toString fwMark} tproxy ip to 127.0.0.1:${toString xrayTproxyPort}
      }
    }
  '';
in
{
  networking.firewall.trustedInterfaces = [ tsIface ];
  networking.firewall.checkReversePath = lib.mkDefault false;

  # networkd removes foreign rules when it configures an interface.
  systemd.network.networks."50-xray-loopback" = lib.mkIf networkd {
    matchConfig.Name = "lo";
    routingPolicyRules = [
      {
        Family = "ipv4";
        FirewallMark = fwMark;
        Table = routeTable;
        Priority = 5209;
      }
    ];
    routes = [
      {
        Destination = "0.0.0.0/0";
        Type = "local";
        Table = routeTable;
      }
      {
        # A marked reverse-path lookup must still reach the tailnet source.
        Destination = "100.64.0.0/10";
        Type = "throw";
        Table = routeTable;
      }
    ];
  };

  networking.firewall.extraCommands =
    lib.optionalString (!networkd) ''
      while ${ip} -4 rule del fwmark ${toString fwMark} lookup ${toString routeTable} 2>/dev/null; do :; done
      ${ip} -4 rule add fwmark ${toString fwMark} lookup ${toString routeTable}
      ${ip} -4 route replace local 0.0.0.0/0 dev lo table ${toString routeTable}
      # Reverse-path checks that honour the mark (src_valid_mark, which tailscaled
      # sets outside nodivert mode, or rpfilter --validmark) look the client's
      # source up in this table. Without the throw it hits the local route and
      # the packet is dropped as a martian.
      ${ip} -4 route replace throw 100.64.0.0/10 table ${toString routeTable}
    ''
    + ''
      ${nft} delete table ip ts_tproxy 2>/dev/null || true
      ${nft} -f ${rulesetFile}
    '';

  networking.firewall.extraStopCommands = ''
    ${nft} delete table ip ts_tproxy 2>/dev/null || true
  ''
  + lib.optionalString (!networkd) ''
    while ${ip} -4 rule del fwmark ${toString fwMark} lookup ${toString routeTable} 2>/dev/null; do :; done
    ${ip} -4 route del local 0.0.0.0/0 dev lo table ${toString routeTable} 2>/dev/null || true
    ${ip} -4 route del throw 100.64.0.0/10 table ${toString routeTable} 2>/dev/null || true
  '';
}
