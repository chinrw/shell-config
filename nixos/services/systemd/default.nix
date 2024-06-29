{ pkgs, ... }: {
  systemd.services.network_proxy = {
    description = "network proxy";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.bash}/bin/bash /home/chin39/Documents/scripts/run.sh";
      Type = "simple";
    };
  };
}
