{ inputs, lib, pkgs, ... }:
let
  # Domestic names use AliDNS and DNSPod directly; other names use dnscrypt-proxy.
  chinaDnsUpstreams =
    let
      chinaDoh = "https://223.5.5.5/dns-query https://doh.pub/dns-query";
    in
    pkgs.runCommand "adguard-china-upstreams" { } ''
      {
        echo "127.0.0.1:5353"
        echo "[/cn/]${chinaDoh}"
        sed -nE 's|^server=/([^/]+)/.*$|[/\1/]${chinaDoh}|p' \
          ${inputs.dnsmasq-china-list}/accelerated-domains.china.conf
      } > $out
    '';
in
{
  imports = [ ./dnscrypt-proxy.nix ];

  services.dnscrypt-proxy.settings = {
    listen_addresses = [ "127.0.0.1:5353" ];
    cache_size = 4096;
  };

  services.adguardhome = {
    enable = true;
    openFirewall = lib.mkDefault true;
    settings = {
      # Covers AdGuard's own HTTP client (filter and version fetches) only.
      # dnsproxy dials upstream_dns without it, so an https:// upstream would
      # be attempted directly and time out.
      http_proxy = "http://127.0.0.1:10809";

      dns = {
        upstream_dns_file = "${chinaDnsUpstreams}";
        upstream_mode = "parallel";
        # DNSPod bootstrap must work independently of the overseas DNS path.
        bootstrap_dns = [
          "223.5.5.5"
          "119.29.29.29"
        ];
        fallback_dns = [
          "1.1.1.1"
          "8.8.8.8"
        ];
      };
    };
  };
}
