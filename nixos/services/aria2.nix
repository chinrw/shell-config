{
  config,
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

      # Resume on restart. The module already sets `save-session` to
      # /var/lib/aria2/aria2.session automatically, so we just need
      # input-file pointing at the same path on startup.
      "input-file" = "/var/lib/aria2/aria2.session";
      # Snapshot the session every 60s so a hard crash (OOM, power
      # loss) loses at most a minute of queue state instead of
      # everything since the last clean shutdown.
      "save-session-interval" = 60;
      # Include completed & errored downloads in the session so their
      # history is preserved across restarts, not just in-progress.
      "force-save" = true;
    };
  };
  users.users.aria2.extraGroups = [ sharedGroup ];

  # The original `umask=0002` in aria2's settings was not a valid
  # aria2 option (it logged "Unknown option: umask=0002"). We don't
  # replicate it at the systemd level either, because:
  #   - Downloads go to /mnt/data/Downloads/aria2 which is a CIFS
  #     mount with file_mode=0775/dir_mode=0775 baked into the
  #     mount options. The server enforces those modes regardless
  #     of the process umask, so UMask would have no effect on
  #     downloaded files.
  #   - The only local file aria2 writes is /var/lib/aria2/aria2.session,
  #     which must NOT be group-writable — the nixpkgs aria2 module
  #     already sets UMask=0022 by default, which is correct for it.
  # Net result: leave the module default alone.

  # Ensure /var/lib/aria2/aria2.session exists before aria2 starts.
  # Without this, the very first startup (or any startup after the
  # file is manually deleted) prints a noisy "Failed to open input
  # file" warning because input-file points at a non-existent path.
  systemd.tmpfiles.rules = [
    "f /var/lib/aria2/aria2.session 0640 aria2 aria2 -"
  ];
}
