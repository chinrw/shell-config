{ config, pkgs, ... }:
{
  systemd.services."rclone_downloader" = {
    description = "rclone baidu netdisk";
    serviceConfig = {
      Type = "simple";
      User = "chin39";
      ExecStart = ''
        ${pkgs.rclone}/bin/rclone move \
                    baidu:baidu/apps/Alist/ \
                    /mnt/data/baidu \
                    --log-systemd \
                    --stats-one-line \
                    --log-level INFO \
                    --transfers 8 \
                    --multi-thread-streams 0 \
                    --timeout 0 \
                    --multi-thread-chunk-size 32M \
                    --delete-empty-src-dirs \
                    --bwlimit 35M
      '';
    };

    # If the command needs extra packages on $PATH
    # path = [ pkgs.curl ];
  };

  systemd.timers."rclone_downloader" = {
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

  # Service to restart rclone_downloader
  systemd.services."rclone_downloader_restart" = {
    description = "Restart rclone service to prevent hanging";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl restart rclone_downloader.service";
    };
  };

  # Timer to restart service every 2 hours to prevent hanging
  systemd.timers."rclone_downloader_restart" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2h";
      OnCalendar = "*:0/120"; # Every 2 hours
      Persistent = true;
    };
  };
}
