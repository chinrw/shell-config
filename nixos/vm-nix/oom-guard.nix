# Post-incident guards.
#
# 2026-07-10 fork storm: ~4M forks under uid 1000. The OOM killer shot the
# small oom_score_adj=200 user services instead of the storm, and nothing
# recorded the spawner. Guards: TasksMax, auditd exec logging (the exec
# logging was withdrawn 2026-08-12, see below).
#
# 2026-07-23 memory exhaustion: ~66 GiB anon (15 rust-analyzer instances
# alone held 33 GiB), no swap. The box thrashed file pages for ~90 min and
# journald died three times under its own audit double-write. Guards: zram
# swap (zram.nix), oomd kill policies, audit rate limit.
{ lib, ... }:
{
  # Task cap per login user, as a drop-in on the user-.slice template.
  # Baseline is ~800 tasks; nix builds run as nixbld outside the slice.
  systemd.slices."user-" = {
    overrideStrategy = "asDropin";
    sliceConfig.TasksMax = 12288;
  };

  security.audit = {
    enable = true;
    rateLimit = 2000;
    backlogLimit = 8192;
    rules = [ ];
  };

  # Audit records stay in auditd's capped log. This socket feeds the
  # journal a second copy (28.6 GiB in one boot); journald.conf Audit=
  # does not gate collection, the socket does. ausearch -k user-exec
  # keeps working.
  systemd.sockets.systemd-journald-audit = {
    enable = false;
    wantedBy = lib.mkForce [ ];
  };

  security.auditd = {
    enable = true;
    # Was 200 MiB x 5 to hold a day of agent execs. With no execve rules
    # only login and AVC records land here, so 150 MiB is ample and the
    # compiled-in 8 MiB rotation is still too small to be useful.
    settings = {
      max_log_file = 50;
      num_logs = 3;
      max_log_file_action = "rotate";
    };
  };

  # oomd only acts on cgroups carrying ManagedOOM* properties. Since
  # 2026-09-06 only the swap trigger is wired: the 80%/30s pressure kill
  # on -.slice and user.slice fired on plain compile load and took the
  # whole login session; swap on the Optane zvol absorbs that load now.
  systemd.oomd = {
    enable = true;
    enableRootSlice = false;
    enableUserSlices = false;
    # Upstream default, kept visible: it is the one number that still
    # decides a kill.
    settings.OOM.SwapUsedLimit = "90%";
  };
  # Swap over SwapUsedLimit: kill the biggest swap consumers.
  systemd.slices."-".sliceConfig.ManagedOOMSwap = "kill";
  # 2G of system.slice (journald, sshd) protected from reclaim.
  systemd.slices."system".sliceConfig.MemoryLow = "2G";
}
