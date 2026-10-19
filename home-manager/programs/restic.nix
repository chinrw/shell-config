{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ (import ../../lib/failure-email.nix).homeManager ];

  # Keep these Home Manager secrets scoped to hosts that enable restic.
  sops.secrets.restic_password = {
    sopsFile = ../../secrets/hosts/vm-nix.yaml;
  };
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
      # A lost machine key is replaced and re-keyed with the admin key, so a
      # copy in the backup only widens who can decrypt the secrets.
      "/home/chin39/.config/sops/age"
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

    backupPrepareCommand = ''
      # Clear stale locks left by interrupted backups.
      ${lib.getExe config.services.restic.backups.vm-nix.package} unlock

      # Trigger the automount and fail if virtiofs is unavailable.
      ${pkgs.coreutils}/bin/ls /mnt/data >/dev/null
    '';

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

  # Every pack is one upload, and OpenList turns each upload into several 115
  # API calls plus a re-list of the parent folder. 64 MiB packs, up from the
  # 16 MiB default, cut those calls to about a quarter. The variable also
  # reaches prune, so repacked data does not fall back to small packs.
  systemd.user.services.restic-backups-vm-nix.Service.Environment = [ "RESTIC_PACK_SIZE=64" ];

  # Ordering: HM sops-nix renders secrets via a user service; wait for it.
  systemd.user.services.restic-backups-vm-nix.Unit.After = [ "sops-nix.service" ];

  # restic returns exit code 3 when it succeeded but some source files
  # were unreadable (e.g. permission-denied perf.data inside a kernel
  # source tree). The snapshot IS saved on exit 3 — only "real" errors
  # are exit 1. Without this, systemd marks the unit failed, short-
  # circuiting the forget/prune/check chain, and OnFailure fires.
  systemd.user.services.restic-backups-vm-nix.Service.SuccessExitStatus = "3";

  # 115's open API sometimes rejects every request for half an hour, longer
  # than the 15 minutes restic retries a backend call before it gives up.
  # Run the unit again once the outage has passed instead of losing the day.
  systemd.user.services.restic-backups-vm-nix.Service.Restart = "on-failure";
  systemd.user.services.restic-backups-vm-nix.Service.RestartSec = "30min";

  # Without RestartMode=direct every failed attempt passes through "failed"
  # and sends its own email. With it, OnFailure fires only when the start
  # limit blocks the next retry. Three starts in 12 hours allows two retries
  # even when every attempt runs for two hours, and the window closes before
  # the next 03:00 run, so a persistent failure still sends one email a day.
  systemd.user.services.restic-backups-vm-nix.Service.RestartMode = "direct";
  systemd.user.services.restic-backups-vm-nix.Unit.StartLimitIntervalSec = "12h";
  systemd.user.services.restic-backups-vm-nix.Unit.StartLimitBurst = 3;

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

  systemd.user.services.restic-backups-vm-nix.Unit.OnFailure = [ "email-failure@%n.service" ];

  assertions = [
    {
      assertion = config.services.restic.backups.vm-nix.paths != [ ];
      message =
        "services.restic.backups.vm-nix.paths is empty. "
        + "Add paths in home-manager/programs/restic.nix before activating.";
    }
  ];
}
