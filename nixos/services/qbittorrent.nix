{
  config,
  pkgs,
  lib,
  ...
}:

let
  qbUser = "qbittorrent"; # ← changed
  port = 8090;
in
{
  environment.systemPackages = [ pkgs.qbittorrent-nox ];

  systemd.services.qbittorrent = {
    description = "qBittorrent (WebUI-only)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "exec";
      User = "chin39";
      Group = "users";
      Environment = "HOME=/var/lib/${qbUser}";
      ExecStart = "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox --webui-port=${builtins.toString port}";

      StateDirectory = qbUser;
      CacheDirectory = qbUser;
      RuntimeDirectory = qbUser;

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      Restart = "on-failure";
      ReadWritePaths = [ "/mnt/data/Video/jellyfin" ]; # :contentReference[oaicite:1]{index=1}
    };
  };

  networking.firewall.allowedTCPPorts = [ port ];
}
