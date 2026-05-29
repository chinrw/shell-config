{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Triggered by systemd's OnFailure when a restic unit fails.
  # Argument $1 = name of the failed unit (passed via %i).
  failureScript = pkgs.writeShellScript "restic-failure-log" ''
    { echo "restic unit $1 failed"
      ${pkgs.systemd}/bin/journalctl --user -u "$1" -n 50 --no-pager
    } | ${pkgs.systemd}/bin/systemd-cat -p emerg -t restic-backup
  '';
in
{
  # Restic-specific secrets co-located with the module that uses them.
  # Only hosts that import this module (currently vm-nix) declare them;
  # other hosts never reference these keys.
  sops.secrets.restic_password = { };
  sops.secrets.restic_rclone_conf = {
    sopsFile = ../../secrets/restic-rclone.conf;
    format = "binary";
  };

  services.restic.enable = true;

  services.restic.backups.vm-nix = {
    initialize = false;
    repository = "rclone:alist:115-open/backup";
    passwordFile = config.sops.secrets.restic_password.path;

    rcloneOptions = {
      # Becomes RCLONE_CONFIG env var inside the unit.
      config = config.sops.secrets.restic_rclone_conf.path;

      # Cap API requests at 1/sec with no burst. alist/115-open
      # returns 405s and read-after-write inconsistency under request
      # bursts — this is the slowest knob that reliably stops the
      # retry storms. Maps to RCLONE_TPSLIMIT / RCLONE_TPSLIMIT_BURST.
      tpslimit = "1";
      tpslimit_burst = "1";
    };

    paths = [
      # User-config (source-of-truth lives in git, but capture local state too)
      "/home/chin39/.config"
      "/home/chin39/.ssh"

      # Personal data
      "/home/chin39/Documents"
      "/home/chin39/.claude"
    ];

    exclude = [
      ".cache"
      "node_modules"
      "target"
      "__pycache__"
      "*.tmp"
      "Trash"
      ".git/objects/pack"
      "build"
      "dist"
      ".venv"
      # perf records often have restrictive perms; without excluding them
      # restic logs "permission denied" and exits 3 ("succeeded with
      # warnings") on every backup.
      "*.perf.data"
      "perf.data"
    ];

    extraBackupArgs = [
      "--tag"
      "vm-nix"
      "--tag"
      "daily"
      "-v"
    ];

    # Force the progress meter on under systemd (restic suppresses it
    # when stdout is not a TTY). 0.2 = one update every 5 seconds —
    # enough to confirm liveness without flooding the journal.
    progressFps = 0.2;

    # Fail loudly if the CIFS mount is unreachable. `ls` on /mnt/data
    # traverses the directory which triggers the systemd automount; on
    # NAS failure the kernel returns I/O error and ls exits non-zero.
    backupPrepareCommand = "${pkgs.coreutils}/bin/ls /mnt/data >/dev/null";

    timerConfig = {
      OnCalendar = "*-*-* 03:00:00";
      Persistent = true;
      AccuracySec = "1min";
    };

    pruneOpts = [
      "--keep-daily"
      "4"
      "--keep-weekly"
      "3"
      "--keep-monthly"
      "2"
      "-v"
    ];

    checkOpts = [
      "--read-data-subset=10%%"
      "-v"
    ];
  };

  # Ordering: HM sops-nix renders secrets via a user service; wait for it.
  systemd.user.services.restic-backups-vm-nix.Unit.After = [ "sops-nix.service" ];

  # restic returns exit code 3 when it succeeded but some source files
  # were unreadable (e.g. permission-denied perf.data inside a kernel
  # source tree). The snapshot IS saved on exit 3 — only "real" errors
  # are exit 1. Without this, systemd marks the unit failed, short-
  # circuiting the forget/prune/check chain, and OnFailure fires.
  systemd.user.services.restic-backups-vm-nix.Service.SuccessExitStatus = "3";

  # Leave the unit completely alone on `home-manager switch`. sd-switch
  # (the default HM activator) honours X-SwitchMethod=keep-old and will
  # NOT start, restart, or stop this unit — even if it changed.
  # Reasoning: a Type=oneshot backup can be running (and a switch would
  # otherwise block waiting), or the unit could be in failed state from
  # the previous cycle (X-RestartIfChanged=false alone doesn't help
  # there — sd-switch still tries to *start* inactive units). The new
  # unit definition still gets installed on disk; it takes effect on
  # the next trigger (timer at 03:00, or manual
  # `systemctl --user start --no-block`).
  systemd.user.services.restic-backups-vm-nix.Service."X-SwitchMethod" = "keep-old";

  # Also keep the restart guard as belt-and-braces (some sd-switch
  # versions check both).
  systemd.user.services.restic-backups-vm-nix.Service."X-RestartIfChanged" = lib.mkForce false;

  # Failure alert: emit emerg-priority journal entry so any future log
  # shipper / alert listener picks it up by priority.
  systemd.user.services.restic-backups-vm-nix.Unit.OnFailure = [ "restic-backup-failed@%p.service" ];

  systemd.user.services."restic-backup-failed@" = {
    Unit.Description = "Log restic backup failure for %i";
    Service = {
      Type = "oneshot";
      ExecStart = "${failureScript} %i";
    };
  };

  assertions = [
    {
      assertion = config.services.restic.backups.vm-nix.paths != [ ];
      message =
        "services.restic.backups.vm-nix.paths is empty. "
        + "Add paths in home-manager/programs/restic.nix before activating.";
    }
  ];
}
