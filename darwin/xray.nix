{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  xrayConfig = config.sops.secrets.xray.path;

  physicalNetworkServices = [
    "Thunderbolt Ethernet Slot 0"
    "AX88x72A"
    "USB 10/100/1000 LAN"
    "Thunderbolt Bridge"
    "Wi-Fi"
    "iPhone USB"
  ];

  # Backport Xray #6095; drop when stable Nixpkgs includes it.
  xrayPatched = pkgs.xray.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../patches/xray/9d9eaf3-close-xhttp-body.patch
    ];
  });

  # sops-install-secrets and Xray are independent launchd daemons. Waiting in
  # the process avoids a boot race without making DNS depend on a GUI login.
  xrayLauncher = pkgs.writeShellScript "xray-wait-config" ''
    cfg=${lib.escapeShellArg xrayConfig}
    until [ -r "$cfg" ]; do
      sleep 1
    done
    exec ${xrayPatched}/bin/xray run -config "$cfg" -format json
  '';

  # macOS reserves port 53 for privileged processes. dnsmasq binds only the
  # loopback address, drops to nobody, and transparently forwards to Xray.
  dnsmasqConfig = pkgs.writeText "xray-dnsmasq.conf" ''
    no-resolv
    no-hosts
    listen-address=127.0.0.1
    bind-interfaces
    port=53
    server=127.0.0.1#1053
    cache-size=0
    keep-in-foreground
    user=nobody
    group=nobody
  '';

  # DNS settings survive daemon reloads and reboots. Restore DHCP while Xray
  # is unavailable, then switch only after both TCP and UDP DNS probes pass.
  xrayDnsSetter = pkgs.writeShellScript "xray-dns-ready" ''
    set -eu

    physical_services=( ${lib.escapeShellArgs physicalNetworkServices} )

    service_exists() {
      /usr/sbin/networksetup -listallnetworkservices 2>/dev/null \
        | /usr/bin/sed '1d; s/^\*//' \
        | ${pkgs.gnugrep}/bin/grep -Fxq "$1"
    }

    dns_ready() {
      /usr/bin/nc -z -w 1 127.0.0.1 53 >/dev/null 2>&1 \
        && [ -n "$(/usr/bin/dig +time=2 +tries=1 +short @127.0.0.1 www.baidu.com A 2>/dev/null)" ]
    }

    if ! dns_ready; then
      for service in "''${physical_services[@]}"; do
        service_exists "$service" || continue
        current_dns=$(/usr/sbin/networksetup -getdnsservers "$service" 2>/dev/null || true)
        if [ "$current_dns" = "127.0.0.1" ]; then
          echo "Xray DNS is unavailable; restoring DHCP DNS for $service"
          /usr/sbin/networksetup -setdnsservers "$service" empty
        fi
      done
    fi

    until dns_ready; do
      sleep 1
    done

    for service in "''${physical_services[@]}"; do
      service_exists "$service" || continue
      echo "Xray DNS is ready; setting $service DNS to 127.0.0.1"
      /usr/sbin/networksetup -setdnsservers "$service" 127.0.0.1
    done
  '';
in
{
  sops = {
    age.keyFile = "/Users/${username}/.config/sops/age/keys.txt";
    secrets.xray = {
      format = "binary";
      sopsFile = ../secrets/mac_xray.conf;
      owner = username;
      mode = "0400";
    };
  };

  environment.systemPackages = [
    xrayPatched
    pkgs.dnsmasq
  ];

  launchd.daemons.xray = {
    serviceConfig = {
      ProgramArguments = [ "${xrayLauncher}" ];
      RunAtLoad = true;
      KeepAlive = true;
      UserName = username;
      ProcessType = "Background";
      StandardOutPath = "/Users/${username}/Library/Logs/xray.out.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/xray.err.log";
    };
  };

  launchd.daemons.xray-dns-forwarder = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.dnsmasq}/bin/dnsmasq"
        "--conf-file=${dnsmasqConfig}"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardOutPath = "/var/log/xray-dns-forwarder.out.log";
      StandardErrorPath = "/var/log/xray-dns-forwarder.err.log";
    };
  };

  # This is deliberately separate from `networking.dns`: nix-darwin applies
  # that option before launchd can prove the new resolver is serving queries.
  # VPN services are absent so Tailscale retains its supplemental MagicDNS.
  launchd.daemons.xray-dns = {
    serviceConfig = {
      ProgramArguments = [ "${xrayDnsSetter}" ];
      RunAtLoad = true;
      KeepAlive.SuccessfulExit = false;
      ProcessType = "Background";
      ThrottleInterval = 5;
      StandardOutPath = "/var/log/xray-dns.out.log";
      StandardErrorPath = "/var/log/xray-dns.err.log";
    };
  };
}
