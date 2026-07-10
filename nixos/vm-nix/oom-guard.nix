# Post-incident hardening for the 2026-07-10 OOM storm.
#
# A fork storm under uid 1000 (~2,200 live bash processes, ~4M forks total)
# exhausted the machine: the OOM killer never targets the individually tiny
# forks, so it shot every oom_score_adj=200 user service instead while the
# storm ran for 10 minutes. Nothing recorded who spawned the forks.
#
# Two guards:
#   1. TasksMax on the user slice — a fork bomb now stalls at the task cap
#      (fork() returns EAGAIN inside the slice) instead of consuming the
#      whole VM. System services and root logins stay usable.
#   2. auditd execve logging for login sessions — the next runaway command
#      is attributable: `ausearch -k user-exec --start <time>`.
{ ... }:
{
  # Cap tasks (processes + threads) per login user. Applied as a drop-in on
  # the user-.slice template so logind's transient user-1000.slice inherits
  # it. Baseline usage is ~800 tasks (rootless docker, syncthing, agents);
  # nix builds run as nixbld outside this slice and are unaffected.
  systemd.slices."user-" = {
    overrideStrategy = "asDropin";
    sliceConfig.TasksMax = 8192;
  };

  security.audit = {
    enable = true;
    # Only execs originating from login sessions (auid is stamped at login
    # and inherited by all descendants, including daemonized ones). Daemons
    # and nix builders have auid unset, keeping volume manageable.
    rules = [
      "-a exit,always -F arch=b64 -F auid=1000 -S execve,execveat -k user-exec"
      "-a exit,always -F arch=b32 -F auid=1000 -S execve,execveat -k user-exec"
    ];
  };

  security.auditd = {
    enable = true;
    # Bound /var/log/audit to ~1 GiB. Left to compiled defaults auditd keeps
    # rotating 8 MiB files, which a busy day of agent execs overruns fast.
    settings = {
      max_log_file = 200;
      num_logs = 5;
      max_log_file_action = "rotate";
    };
  };
}
