{ config, lib, ... }:
let
  cfg = config.services.tailscale.derper;
in
{
  services.tailscale.derper = {
    enable = true;
    domain = "112.126.64.56";
    port = 9001;
    stunPort = 34789;
    configureNginx = false;
    verifyClients = true;
    # Client verification requires derper and tailscaled from the same revision.
    package = config.services.tailscale.package.derper;
  };

  # The module opens its STUN port; direct TLS also needs the TCP listener.
  networking.firewall.allowedTCPPorts = [ cfg.port ];
  systemd.services.tailscale-derper = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    serviceConfig.ExecStart = lib.mkForce (
      "${lib.getExe' cfg.package "derper"}"
      + " -a :${toString cfg.port} -hostname=${cfg.domain}"
      + " -c /var/lib/derper/derper.key"
      # IP certificates persist across restarts. Their SHA256 is pinned in DERPMap.
      + " -certmode manual -certdir /var/lib/derper/certs"
      + " -http-port=-1 -stun=true -stun-port ${toString cfg.stunPort} -verify-clients"
    );
  };
}
