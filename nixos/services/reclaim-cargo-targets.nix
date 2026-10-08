{
  lib,
  pkgs,
  username,
  ...
}:
{
  systemd.services.cargo-target-reclaim = {
    description = "Reclaim idle Cargo build caches";
    path = [ pkgs.coreutils ];
    environment.NO_SYSLOG = "1";
    serviceConfig = {
      Type = "oneshot";
      # Root can inspect other users' processes before reclaiming a cache.
      User = "root";
      ExecStart = lib.escapeShellArgs [
        "${pkgs.python3}/bin/python3"
        "${./reclaim-cargo-targets/reclaim_cargo_targets.py}"
        "--apply"
        "--root"
        "/tmp"
        "--root"
        "/home/${username}/.cache"
        "--root"
        "/home/${username}/Documents/play/stocks/.claude/worktrees"
      ];
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.cargo-target-reclaim = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "5min";
      Persistent = true;
    };
  };
}
