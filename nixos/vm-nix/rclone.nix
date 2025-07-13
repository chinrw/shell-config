{ config, pkgs, ... }:
{
  systemd.services."rclone_downloader" = {
    description = "rclone baidu netdisk";
    serviceConfig = {
      Type = "oneshot";
      User = "chin39";
      ExecStart = "${pkgs.rclone}/bin/rclone move -v baidu:baidu/apps/Alist/ /mnt/data/baidu \
                    --transfers 4 --multi-thread-streams 0 --timeout 0 \
                    --multi-thread-chunk-size 32M --delete-empty-src-dirs";
    };

    # If the command needs extra packages on $PATH
    # path = [ pkgs.curl ];
  };

  systemd.timers."rclone_download" = {
    wantedBy = [ "timers.target" ]; # auto-start at boot
    timerConfig = {
      # First run 5 min after boot, then every 15 min
      OnBootSec = "5min";
      OnUnitActiveSec = "10min";

      # Nice-to-haves (optional)
      Persistent = true; # catch up on missed runs after suspend/offline
      AccuracySec = "1min";
    };
  };
}

