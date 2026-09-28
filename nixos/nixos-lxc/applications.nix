{ config, ... }:
{
  virtualisation.oci-containers.backend = "docker";
  virtualisation.oci-containers.containers = {
    alist = {
      autoStart = true;
      image = "openlistteam/openlist@sha256:783471c2e72f6430d7a8fa21361ab5d1ce01d810b7418125d484c50b467c396c";
      user = "1000:100";
      environment = {
        TZ = "Asia/Shanghai";
        UMASK = "022";
      };
      volumes = [
        "/home/chin39/Documents/container/alist/openlist:/opt/openlist/data"
      ];
      extraOptions = [ "--network=host" ];
    };
    lanraragi = {
      autoStart = true;
      image = "difegue/lanraragi@sha256:6376a3de75c8a4045aadeb252eee9661ee9baf27965cec7a405a2b246d2937b3";
      environment = {
        LRR_UID = "1000";
        LRR_GID = "100";
        LRR_AUTOFIX_PERMISSIONS = "-1";
        http_proxy = "http://192.168.0.240:10809";
        https_proxy = "http://192.168.0.240:10809";
        no_proxy = config.networking.proxy.noProxy;
        NO_PROXY = config.networking.proxy.noProxy;
      };
      ports = [ "3001:3000" ];
      volumes = [
        "/home/chin39/Documents/container/lanraragi/perl5:/home/koyomi/perl5"
        "/mnt/data/harmony/本子:/home/koyomi/lanraragi/content"
        "/home/chin39/Documents/container/lanraragi/database:/home/koyomi/lanraragi/database"
        "/home/chin39/Documents/container/lanraragi/thumb:/home/koyomi/lanraragi/thumb"
        "/home/chin39/Documents/container/lanraragi/plugins:/home/koyomi/lanraragi/lib/LANraragi/Plugin/Sideloaded"
      ];
    };
  };
  systemd.services.docker-alist = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
  };
  systemd.services.docker-lanraragi.unitConfig.RequiresMountsFor = [ "/mnt/data" ];
  networking.firewall.allowedTCPPorts = [ 5244 5246 3001 ];
}
