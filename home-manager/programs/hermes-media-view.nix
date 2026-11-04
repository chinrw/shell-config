{ config, pkgs, ... }:
let
  source = "${config.home.homeDirectory}/mounts/alist/115-open/bk_plain/video";
  view = "${config.home.homeDirectory}/mounts/hermes-video/video";
  waitForMount = pkgs.writeShellScript "wait-for-hermes-video-view" ''
    for attempt in $(seq 1 50); do
      if ${pkgs.util-linux}/bin/mountpoint -q ${view}; then
        exit 0
      fi
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    exit 1
  '';
in
{
  systemd.user.services.hermes-video-view = {
    Unit = {
      Description = "Writable video mount view for Hermes";
      Requires = [ "rclone-alist.service" ];
      After = [ "rclone-alist.service" ];
      PartOf = [ "rclone-alist.service" ];
    };
    Install.WantedBy = [ "rclone-alist.service" ];
    Service = {
      Type = "simple";
      UMask = "0022";
      ExecStartPre = [
        "-/run/wrappers/bin/fusermount3 -uz ${view}"
        "${pkgs.coreutils}/bin/install -d -m 0755 ${view}"
        "${pkgs.coreutils}/bin/test -d ${source}"
        "${pkgs.util-linux}/bin/mountpoint -q ${config.home.homeDirectory}/mounts/hermes-video"
      ];
      # The view grants Hermes owner access while rclone keeps the host user's ownership.
      ExecStart = "${pkgs.bindfs}/bin/bindfs -f --mirror-only=hermes --perms=u+rwX:g-rwx:o-rwx --create-as-mounter ${source} ${view}";
      ExecStartPost = "${waitForMount}";
      ExecStop = "/run/wrappers/bin/fusermount3 -u ${view}";
      ExecStopPost = "-/run/wrappers/bin/fusermount3 -uz ${view}";
      Environment = [ "PATH=/run/wrappers/bin:${pkgs.coreutils}/bin" ];
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
