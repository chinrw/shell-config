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
  remoteRepository = "rclone:alist:115-open/backup";
  # Each host has one daily backup; source path changes must not create a new retention group.
  retentionOptions = [
    "--group-by"
    "host"
    "--keep-daily"
    "4"
    "--keep-weekly"
    "3"
    "--keep-monthly"
    "2"
    "-v"
  ];

  upload = pkgs.writeShellApplication {
    name = "restic-upload-vm-nix";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.restic
      pkgs.util-linux
    ];
    text = ''
      ls /mnt/data >/dev/null
      mountpoint -q /mnt/data
      restic --repo ${lib.escapeShellArg backup.repository} unlock
      restic --retry-lock 30m --repo ${lib.escapeShellArg backup.repository} \
        forget --prune --tag daily --max-unused=0 ${lib.escapeShellArgs retentionOptions}
      restic --retry-lock 30m --repo ${lib.escapeShellArg backup.repository} check -v
      restic unlock
      restic --retry-lock 30m copy --from-repo ${lib.escapeShellArg backup.repository} \
        --from-password-file "$RESTIC_PASSWORD_FILE" -v
      restic --retry-lock 30m forget --prune --tag daily --max-unused=5% \
        ${lib.escapeShellArgs retentionOptions}
      restic --retry-lock 30m check --read-data-subset=10% -v
    '';
  };
in
{
  sops.secrets.restic_rclone_conf = {
    sopsFile = ../../secrets/restic-rclone.conf;
    format = "binary";
  };

  systemd.user.services.${backupUnit}.Unit.OnSuccess = [ "restic-upload-vm-nix.service" ];

  systemd.user.services.restic-upload-vm-nix = {
    Unit = {
      Description = "Copy shared restic snapshots to 115";
      After = [
        "sops-nix.service"
        "${backupUnit}.service"
      ];
      OnFailure = [ "email-failure@%n.service" ];
      StartLimitIntervalSec = "12h";
      StartLimitBurst = 3;
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe upload;
      Environment = [
        "RESTIC_REPOSITORY=${remoteRepository}"
        "RESTIC_PASSWORD_FILE=${backup.passwordFile}"
        "RESTIC_CACHE_DIR=%C/restic-upload-vm-nix"
        "RESTIC_PACK_SIZE=64"
        "RESTIC_COMPRESSION=max"
        "RESTIC_PROGRESS_FPS=0.2"
        "RCLONE_CONFIG=${config.sops.secrets.restic_rclone_conf.path}"
        # 115 rejects bursts even when the individual uploads are small.
        "RCLONE_TPSLIMIT=1"
        "RCLONE_TPSLIMIT_BURST=1"
      ];
      CacheDirectory = "restic-upload-vm-nix";
      CacheDirectoryMode = "0700";
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = "30min";
      RestartMode = "direct";
      "X-SwitchMethod" = "keep-old";
      "X-RestartIfChanged" = false;
    };
  };
}
