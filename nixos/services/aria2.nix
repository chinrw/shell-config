{
  config,
  lib,
  pkgs,
  username,
  sharedGroup,
  ...
}:
{
  sops = {
    age.keyFile = "/home/${username}/.config/sops/age/keys.txt"; # must have no password!
    defaultSopsFile = ../../secrets/hosts.yaml;
    defaultSopsFormat = "yaml";

    secrets = {
      "aria2-token" = { };
    };
  };
  services.aria2 = {
    enable = true;
    rpcSecretFile = config.sops.secrets."aria2-token".path;
    openPorts = true;

    settings = {
      dir = "/mnt/data/Downloads/aria2";
      enable-rpc = true;
      "disable-ipv6" = true;
      "rpc-listen-all" = true;
      "rpc-allow-origin-all" = true;
      "auto-file-renaming" = false;
      "max-concurrent-downloads" = 10;
      # Retry indefinitely with a 30s cooldown between attempts.
      # Default is max-tries=5, retry-wait=0 (5 rapid-fire retries
      # then permanent failure). 0 = unlimited retries.
      "max-tries" = 0;
      "retry-wait" = 600;

      # Resume on restart. The module already sets `save-session` to
      # /var/lib/aria2/aria2.session automatically, so we just need
      # input-file pointing at the same path on startup.
      "input-file" = "/var/lib/aria2/aria2.session";
      # Snapshot the session every 60s so a hard crash (OOM, power
      # loss) loses at most a minute of queue state instead of
      # everything since the last clean shutdown.
      "save-session-interval" = 60;
      # Do NOT enable `force-save` — despite its innocent-sounding
      # name, it causes aria2 to retain the `.aria2` control file
      # next to every completed download forever (the option is
      # designed for BitTorrent seeding state, not HTTP history).
      # Standard save-session already handles restart-resume for
      # in-progress downloads; completed ones don't need their
      # control files preserved.
    };
  };
  users.users.aria2.extraGroups = [ sharedGroup ];

  # The original `umask=0002` in aria2's settings was not a valid aria2
  # option (it logged "Unknown option: umask=0002"). We leave the nixpkgs
  # module's UMask=0022 unchanged because:
  #   - Downloads go to /mnt/data/Downloads/aria2, a virtiofs share
  #     whose host directories carry POSIX default ACLs granting group
  #     `users` rwx (see vm-nix/default.nix); inherited default ACLs govern
  #     group access there instead of the process umask.
  #   - The local /var/lib/aria2/aria2.session file must not be group-writable.
  #
  # The nixpkgs aria2 module also emits a tmpfiles rule that would chown the
  # download directory to aria2:aria2 and chmod it 0770 on every boot/switch.
  # UID/GID pass through virtiofs, so that destroys the host-side owner and
  # setgid/group-sharing state managed outside this config. systemd-tmpfiles
  # uses the first rule for a path; mkBefore puts this rule ahead of the
  # module's hardcoded one (the module's later duplicate line is ignored with
  # a harmless "Duplicate line for path" journal warning). The ":" prefixes
  # mean mode/owner apply only if the directory has to be created — an
  # existing directory is never chmodded or chowned, so tmpfiles leaves the
  # share entirely alone.

  systemd.tmpfiles.rules = lib.mkBefore [
    "d '${config.services.aria2.settings.dir}' :2775 :${username} :${sharedGroup} - -"

    # Ensure the session file exists before aria2 starts, avoiding a noisy
    # "Failed to open input file" warning on the first startup.
    "f /var/lib/aria2/aria2.session 0640 aria2 aria2 -"
  ];
}
