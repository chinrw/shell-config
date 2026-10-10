{ lib, pkgs, ... }:
let
  stateDir = "/var/lib/openlist";
in
{
  users.groups.openlist = { };
  users.users.openlist = {
    isSystemUser = true;
    group = "openlist";
    # The Local storage driver writes into /mnt/data, whose default ACLs grant
    # the users group rwx.
    extraGroups = [ "users" ];
    home = stateDir;
  };

  systemd.services.openlist = {
    description = "OpenList";
    wantedBy = [ "multi-user.target" ];
    requires = [ "postgresql.service" ];
    after = [
      "postgresql.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ "/mnt/data" ];
    environment.TZ = "Asia/Shanghai";
    serviceConfig = {
      User = "openlist";
      Group = "openlist";
      UMask = "0022";
      StateDirectory = "openlist";
      StateDirectoryMode = "0750";
      # config.json still holds the container's relative paths such as
      # data/temp, and they resolve against the working directory.
      WorkingDirectory = stateDir;
      ExecStart = "${lib.getExe pkgs.openlist} server --data ${stateDir}/data --no-prefix";
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/mnt/data" ];
    };
  };

  # 5221 (FTP) stays closed, as it was for the container.
  networking.firewall.allowedTCPPorts = [
    5244
    5246
  ];
}
