{ ... }:
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
  };
  systemd.services.docker-alist = {
    requires = [ "postgresql.service" ];
    after = [ "postgresql.service" ];
  };
  networking.firewall.allowedTCPPorts = [ 5244 5246 3001 ];
}
