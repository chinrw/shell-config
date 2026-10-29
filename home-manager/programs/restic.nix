{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:
let
  backup = config.services.restic.backups.${hostname};
  backupUnit = "restic-backups-${hostname}";
  home = config.home.homeDirectory;
in
{
  imports = [ (import ../../lib/failure-email.nix).homeManager ];

  sops.secrets.restic_password = {
    sopsFile = ../../secrets/restic-password;
    format = "binary";
  };

  services.restic.enable = true;

  services.restic.backups.${hostname} = {
    initialize = false;
    repository = "/mnt/data/backup/restic";
    passwordFile = config.sops.secrets.restic_password.path;

    paths = [
      "${home}/Documents"
      "${home}/.*"
    ];

    exclude = [
      ".cache"
      # A lost machine key is replaced and re-keyed with the admin key, so a
      # copy in the backup only widens who can decrypt the secrets.
      "${home}/.config/sops/age"
    ];

    extraBackupArgs = [
      "--host=${hostname}"
      "--group-by=host"
      "--retry-lock=30m"
      "--one-file-system"
      "--tag"
      hostname
      "--tag"
      "daily"
      "-v"
    ];

    # Force the progress meter on under systemd (restic suppresses it
    # when stdout is not a TTY). 0.2 = one update every 5 seconds —
    # enough to confirm liveness without flooding the journal.
    progressFps = 0.2;

    backupPrepareCommand = ''
      set -euo pipefail
      ${pkgs.coreutils}/bin/ls /mnt/data >/dev/null
      ${pkgs.util-linux}/bin/mountpoint -q /mnt/data
      ${lib.getExe backup.package} unlock
    '';

    timerConfig = {
      OnCalendar = lib.mkDefault "*-*-* 03:00:00";
      Persistent = true;
      AccuracySec = "1min";
    };

    checkOpts = [
      "--retry-lock=30m"
      "--read-data-subset=10%%"
      "-v"
    ];
  };

  systemd.user.services.${backupUnit} = {
    Unit = {
      After = [ "sops-nix.service" ];
      OnFailure = [ "email-failure@%n.service" ];
      StartLimitIntervalSec = "12h";
      StartLimitBurst = 3;
    };
    Service = {
      # Larger packs reduce the number of uploads through OpenList's 115 backend.
      Environment = [
        "RESTIC_PACK_SIZE=64"
        "RESTIC_COMPRESSION=max"
      ];
      # Exit 3 still saves a snapshot, although some source files were unreadable.
      SuccessExitStatus = "3";
      Restart = "on-failure";
      RestartSec = "30min";
      # Notify only after the retry limit is exhausted.
      RestartMode = "direct";
      # Switching Home Manager must not interrupt or start a backup.
      "X-SwitchMethod" = "keep-old";
      "X-RestartIfChanged" = lib.mkForce false;
    };
  };
}
