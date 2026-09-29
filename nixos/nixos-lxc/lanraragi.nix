{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.lanraragi = {
    enable = true;
    port = 3001;
    redis.port = 6381;
  };

  services.redis = {
    package = pkgs.valkey;
    servers.lanraragi = {
      bind = "127.0.0.1";
      appendOnly = true;
      settings.dbfilename = lib.mkForce "database.rdb";
    };
  };

  users.groups.lanraragi = { };
  users.users.lanraragi = {
    isSystemUser = true;
    group = "lanraragi";
    extraGroups = [ "users" ];
  };

  systemd.services.lanraragi = {
    unitConfig.RequiresMountsFor = [ "/mnt/data" ];
    environment = config.networking.proxy.envVars // {
      PERL5LIB = "/var/lib/lanraragi/plugins";
      LRR_THUMB_DIRECTORY = "/var/lib/lanraragi/thumb";
    };
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "lanraragi";
      Group = "lanraragi";
      EnvironmentFile = "/var/lib/lanraragi-private/environment";
      UMask = "0002";
    };
    # The upload handler writes under ./lib, while Perl discovers plugins via PERL5LIB.
    preStart = lib.mkAfter ''
      mkdir -p plugins/LANraragi/Plugin/Sideloaded thumb
      ln -sfn plugins lib
    '';
  };
}
