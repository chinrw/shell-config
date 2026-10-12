{
  config,
  lib,
  pkgs,
  ...
}:
{
  sops.secrets.lanraragi-environment = {
    sopsFile = ../../secrets/lanraragi.env;
    format = "dotenv";
    key = "";
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ "lanraragi.service" ];
  };

  services.lanraragi = {
    enable = true;
    port = 3001;
    openFirewall = true;
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

  # The thumbnails and the redis database came from CT107 with these ids, so
  # pinning them keeps the copied state owned by the right users without a
  # recursive chown.
  users.groups.lanraragi.gid = 995;
  users.users.lanraragi = {
    uid = 996;
    isSystemUser = true;
    group = "lanraragi";
    extraGroups = [ "users" ];
  };
  users.groups.redis-lanraragi.gid = 994;
  users.users.redis-lanraragi.uid = 995;

  systemd.services.lanraragi = {
    unitConfig.RequiresMountsFor = [ "/mnt/data" ];
    environment = config.networking.proxy.envVars // {
      # Mojolicious needs this flag to honor the inherited proxy variables.
      MOJO_PROXY = "1";
      PERL5LIB = "/var/lib/lanraragi/plugins";
      LRR_THUMB_DIRECTORY = "/var/lib/lanraragi/thumb";
    };
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "lanraragi";
      Group = "lanraragi";
      EnvironmentFile = config.sops.secrets.lanraragi-environment.path;
      UMask = "0002";
    };
    # The upload handler writes under ./lib, while Perl discovers plugins via PERL5LIB.
    preStart = lib.mkAfter ''
      mkdir -p plugins/LANraragi/Plugin/Sideloaded thumb
      ln -sfn plugins lib
    '';
  };
}
