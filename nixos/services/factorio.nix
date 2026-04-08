{
  config,
  pkgs,
  lib,
  ...
}:

{
  services.factorio = {
    enable = true;
    openFirewall = true;

    package = pkgs.factorio-headless;

    # Save management
    saveName = "main";
    loadLatestSave = true;
    autosave-interval = 10; # minutes — each autosave is an SMB write now
    nonBlockingSaving = true;

    # Server identity / visibility
    game-name = "chin39's Factorio";
    description = "";
    lan = true;
    public = false;
    requireUserVerification = false;

    # Admins get /promote etc. in-game
    admins = [ "chin39" ];

    # NOTE: `mods` is intentionally left unset.
    #
    # When `mods = []`, the module does NOT pass `--mod-directory`,
    # so factorio-headless falls back to its default location derived
    # from `write-data` in the generated config file, which is:
    #
    #     /var/lib/factorio/mods/
    #
    # That path is bind-mounted onto the SMB share below — see the
    # BindPaths= block. Drop third-party mod zips directly into
    #
    #     /mnt/data/Documents/Factorio/mods/
    #
    # from any machine with access to the share (no sudo on the VM,
    # no DynamicUser shenanigans), then `systemctl restart factorio`.
    #
    # IMPORTANT — Space Age DLC is ALREADY BUNDLED.
    #   nixpkgs' factorio-headless is built with `releaseType = space-age`
    #   (check the startup log: "Factorio 2.0.76 (...headless, space-age)").
    #   The three DLC "mods" — space-age, elevated-rails, quality — ship
    #   inside the package's own share/factorio/data/ directory and are
    #   always loaded. Do NOT copy these from a Steam install into the
    #   mods/ folder on the share; factorio will see them in both places
    #   and crash with `Error Util.cpp:81: Duplicate mod <name>.`
    #
    # Do NOT set `mods = [ ... ]` later — it makes the module pass
    # --mod-directory pointing at a read-only /nix/store path and the
    # writable share directory would be ignored.
  };

  # ---------------------------------------------------------------
  # Saves AND mods live on the SMB share, not on the VM's root disk.
  #
  # Layout on the share (create these once, as chin39):
  #
  #   /mnt/data/Documents/Factorio/
  #     ├── saves/
  #     │   └── main.zip          ← drop your existing save here
  #     └── mods/
  #         ├── mod-list.json     ← auto-generated on first run
  #         ├── mod-settings.dat  ← optional, per-mod settings
  #         └── *.zip             ← drop mod zips here
  #
  # Inside the service mount namespace, both directories are bind-
  # mounted onto the factorio state dir, so factorio-headless reads
  # and writes them as if they were local. Autosaves and mod-list
  # updates are persisted to the SMB share automatically.
  #
  # Permissions:
  #   The CIFS mount in vm-nix/default.nix uses uid=1000, gid=users,
  #   file_mode=0775. The factorio service runs as a DynamicUser
  #   (random UID each boot), so we can't match uid=1000. Instead
  #   we add the dynamic user to the `users` group (gid 100) via
  #   SupplementaryGroups, which gives it group rwx on the share.
  #
  # Ordering:
  #   RequiresMountsFor triggers the x-systemd.automount on /mnt/data
  #   and blocks the service until the CIFS mount is actually up. If
  #   the SMB server is unreachable at boot, factorio stays down
  #   (acceptable — better than running on an empty saves/mods dir).
  # ---------------------------------------------------------------
  systemd.services.factorio = {
    unitConfig.RequiresMountsFor = [
      "/mnt/data/Documents/Factorio/saves"
      "/mnt/data/Documents/Factorio/mods"
    ];
    serviceConfig = {
      SupplementaryGroups = [ "users" ];
      BindPaths = [
        "/mnt/data/Documents/Factorio/saves:/var/lib/factorio/saves"
        "/mnt/data/Documents/Factorio/mods:/var/lib/factorio/mods"
      ];
    };
  };
}
