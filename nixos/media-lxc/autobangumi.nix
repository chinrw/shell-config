{ ... }:
let
  stateDir = "/var/lib/autobangumi";
  oci = import ../../lib/oci-images.nix;
in
{
  virtualisation.oci-containers = {
    backend = "docker";
    containers.autobangumi = {
      image = oci.ref "auto-bangumi";
      volumes = [
        "${stateDir}/config:/app/config"
        "${stateDir}/data:/app/data"
      ];
      environment = {
        PUID = "1000";
        PGID = "100";
        TZ = "Asia/Shanghai";
        UMASK = "022";
      };
      extraOptions = [
        # The downloader is qbittorrent on this host, and its WebUI skips
        # authentication only for LAN source addresses.
        "--network=host"
        # The image probes localhost, which busybox resolves to ::1 while the
        # app listens on IPv4 only, so the stock check always fails.
        "--health-cmd=wget -qO- http://127.0.0.1:7892/health || exit 1"
      ];
    };
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0750 chin39 users -"
    "d ${stateDir}/config 0750 chin39 users -"
    "d ${stateDir}/data 0750 chin39 users -"
  ];

  networking.firewall.allowedTCPPorts = [ 7892 ];
}
