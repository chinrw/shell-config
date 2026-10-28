{ config, ... }:
let
  address = "chinqrw@gmail.com";
  origin = "http://192.168.0.241:9080";
in
{
  sops.secrets."email/smtp-password" = {
    sopsFile = ../../secrets/email.yaml;
    key = "smtp-password";
  };
  sops.templates."ntfy.env" = {
    content = ''
      NTFY_SMTP_SENDER_PASS=${config.sops.placeholder."email/smtp-password"}
    '';
    restartUnits = [ "ntfy-sh.service" ];
  };

  services.ntfy-sh = {
    enable = true;
    environmentFile = config.sops.templates."ntfy.env".path;
    settings = {
      base-url = origin;
      listen-http = "127.0.0.1:2586";
      auth-default-access = "read-write";
      # Updater failures include up to 12 KB of redacted journal output.
      message-size-limit = "64k";
      visitor-email-limit-burst = 10;
      visitor-email-limit-replenish = "6s";
      smtp-sender-addr = "127.0.0.1:2525";
      smtp-sender-user = address;
      smtp-sender-from = address;
    };
  };
  systemd.services.ntfy-sh = {
    wants = [ "stunnel.service" ];
    after = [ "stunnel.service" ];
  };

  services.stunnel = {
    enable = true;
    clients.ntfy-gmail = {
      accept = "127.0.0.1:2525";
      connect = "127.0.0.1:10809";
      protocol = "connect";
      protocolHost = "smtp.gmail.com:465";
      checkHost = "smtp.gmail.com";
      sni = "smtp.gmail.com";
      # Certificate validation must not open a separate, unproxied OCSP connection.
      OCSPaia = false;
      TIMEOUTconnect = 15;
      TIMEOUTidle = 60;
    };
  };
  systemd.services.stunnel = {
    wants = [ "xray.service" ];
    after = [ "xray.service" ];
  };

  services.caddy.virtualHosts.${origin} = {
    listenAddresses = [ "192.168.0.241" ];
    extraConfig = ''
      @lan remote_ip 192.168.0.0/24
      handle @lan {
        request_body {
          max_size 64KiB
        }
        reverse_proxy 127.0.0.1:2586 {
          header_up X-Email ${address}
        }
      }
      respond 403
    '';
  };
  networking.firewall.interfaces.eth0.allowedTCPPorts = [ 9080 ];
}
