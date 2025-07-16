{ config, pkgs, lib, ... }:

let
  qbUser = "qbittorrent";   # ← changed
  port = 8090;
in
{
  users.users.${qbUser} = {
    isSystemUser = true;
    description = "qBittorrent service account";
    group = qbUser;
    home = "/var/lib/${qbUser}";
  };

  users.groups.${qbUser} = { };

  environment.systemPackages = [ pkgs.qbittorrent-nox ];

  systemd.services.qbittorrent = {
    description = "qBittorrent (WebUI-only)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "exec";
      User = qbUser;
      Group = qbUser;
      Environment = "HOME=/var/lib/${qbUser}";
      ExecStart = "${pkgs.qbittorrent-nox}/bin/qbittorrent-nox --webui-port=${port}";

      StateDirectory = qbUser;
      CacheDirectory = qbUser;
      RuntimeDirectory = qbUser;

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      Restart = "on-failure";
    };
  };

  networking.firewall.allowedTCPPorts = [ port ];
}

