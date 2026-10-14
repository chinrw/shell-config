{ config, lib, ... }:
let
  zone = "home.midashood.top";
  lanAddress = "192.168.0.241";
  tailAddress = "100.67.38.92";
  backends = {
    openlist = "127.0.0.1:5244";
    lrr = "127.0.0.1:3001";
    jellyfin = "127.0.0.1:8096";
  };
in
{
  sops.secrets.namesilo-api-key = {
    key = "api_key";
    mode = "0400";
  };

  security.acme = {
    acceptTerms = true;
    certs.${zone} = {
      domain = "*.${zone}";
      email = "cocorobinkiller@gmail.com";
      dnsProvider = "namesilo";
      # Internal DNS must not hide the public challenge records during renewal.
      dnsResolver = "8.8.8.8:53";
      # NameSilo TXT records have a one-hour TTL; recursive caches can retain an older challenge.
      extraLegoFlags = [ "--dns.propagation.disable-rns" ];
      credentialFiles.NAMESILO_API_KEY_FILE = config.sops.secrets.namesilo-api-key.path;
    };
  };
  systemd.services."acme-order-renew-${zone}".environment.NAMESILO_PROPAGATION_TIMEOUT = "1800";

  services.caddy = {
    enable = true;
    openFirewall = false;
    virtualHosts = lib.mapAttrs' (
      name: upstream:
      lib.nameValuePair "${name}.${zone}" {
        useACMEHost = zone;
        listenAddresses = [ "0.0.0.0" ];
        extraConfig = "reverse_proxy ${upstream}";
      }
    ) backends;
  };

  services.adguardhome.settings = {
    dns.bind_hosts = [ tailAddress ];
    filtering.rewrites = lib.mapAttrsToList (name: _: {
      domain = "${name}.${zone}";
      answer = lanAddress;
      enabled = true;
    }) backends;
  };
  # tailscaled counts as started before tailscale0 holds its address, and AdGuard
  # exits fatally when a bind_hosts entry cannot be bound. The target waits for the IP.
  systemd.services.adguardhome = {
    wants = [ "tailscale-online.target" ];
    after = [ "tailscale-online.target" ];
  };

  networking.firewall = {
    interfaces.tailscale0 = {
      allowedTCPPorts = [
        53
        80
        443
      ];
      allowedUDPPorts = [ 53 ];
    };
    interfaces.eth0.allowedTCPPorts = [
      80
      443
    ];
  };
}
