# stateDir holds config-jellyfin and cache, the two directories the old
# container mounted at /config and /cache.
{ stateDir }:
{ pkgs, config, ... }:
let
  mountsDir = "/home/chin39/mounts";
  mediaDir = "/mnt/data/Video/jellyfin";
  jellyfinCjkFonts = pkgs.symlinkJoin {
    name = "jellyfin-cjk-fonts";
    paths = [
      pkgs.noto-fonts-cjk-sans
      pkgs.noto-fonts-cjk-serif
    ];
  };
in
{
  services.jellyfin = {
    enable = true;
    user = "chin39";
    group = "users";
    dataDir = "${stateDir}/config-jellyfin";
    cacheDir = "${stateDir}/cache";
  };

  systemd.services.jellyfin = {
    environment = config.networking.proxy.envVars;
    path = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    # The library is on the rclone FUSE mount. The check runs inside the
    # service's mount namespace, so it sees the binds jellyfin will read, and
    # an empty mount point does not count as ready.
    preStart = ''
      for _ in $(seq 30); do
        if mountpoint -q /mounts/alist \
          && [ -n "$(ls -A /mounts/alist | head -n1)" ] \
          && [ -n "$(ls -A /jellyfin-media | head -n1)" ]; then
          exit 0
        fi
        sleep 2
      done
      echo "media mounts are not ready" >&2
      exit 1
    '';
    unitConfig = {
      RequiresMountsFor = [
        mediaDir
        stateDir
      ];
      # Keep retrying while rclone is down. The next start re-runs the check.
      StartLimitIntervalSec = 0;
    };
    serviceConfig = {
      # The mount check can take 60s, longer than the module's 15s.
      TimeoutStartSec = "90s";
      # The module's 15s also bounds shutdown, and a SIGKILL mid-shutdown
      # can leave the SQLite library half written.
      TimeoutStopSec = "60s";
      RestartSec = "30s";
      # The database and system.xml hold the container's paths (/config,
      # /cache, /jellyfin-media, /mounts). Binding them keeps every stored
      # path valid without rewriting the library.
      BindPaths = [
        "${stateDir}/config-jellyfin:/config"
        "${stateDir}/cache:/cache"
        "${mediaDir}:/jellyfin-media"
        "${mountsDir}:/mounts"
      ];
      # encoding.xml points FallbackFontPath at /config/fonts.
      BindReadOnlyPaths = [ "${jellyfinCjkFonts}/share/fonts/opentype/noto-cjk:/config/fonts" ];
    };
  };
}
