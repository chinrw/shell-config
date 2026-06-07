# Xray client — macOS launchd user agent.
#
# NixOS hosts run Xray as a system service (`services.xray`, see
# nixos/vm-nix/default.nix). nix-darwin has no equivalent module, so on
# macOS we run the same pinned `pkgs.xray` (overlays/default.nix) as a
# per-user launchd agent that starts at login.
#
# Imported via programs/darwin/default.nix (macOS only).
{ config, lib, pkgs, ... }:
let
  # Concrete on darwin, e.g. /Users/chin39/.config/sops-nix/secrets/xray.
  xrayConfig = config.sops.secrets."xray".path;

  # launchd has no systemd-style `After=`/`Requires=`. sops-nix decrypts this
  # config from its *own* login agent (org.nix-community.home.sops-nix, also
  # RunAtLoad), so at boot the two agents race and Xray usually loses — it
  # starts before the file exists and dies with "no such file or directory".
  # The path also resolves through a symlink sops-nix recreates every login,
  # which makes launchd's `KeepAlive.PathState` watching miss the file and
  # never relaunch. So gate startup in the program itself: block until the
  # decrypted config resolves, then hand off to the real binary with exec
  # (keeps launchd tracking the Xray PID for KeepAlive).
  xrayLauncher = pkgs.writeShellScript "xray-wait-config" ''
    cfg=${lib.escapeShellArg xrayConfig}
    i=0
    while [ "$i" -lt 60 ]; do
      if [ -e "$cfg" ]; then
        exec ${pkgs.xray}/bin/xray run -config "$cfg" -format json
      fi
      sleep 1
      i=$((i + 1))
    done
    echo "xray-wait-config: $cfg still absent after 60s; sops-nix never decrypted it" >&2
    exit 1
  '';
in
{
  # secrets/mac_xray.conf is a sops *binary* file (opaque JSON payload) —
  # a macOS-specific copy of secrets/xray.conf so the Mac's inbounds can
  # diverge from the NixOS host (e.g. listen on 127.0.0.1 only). Encrypted
  # for the `chin39` age key home-manager sops already uses; no re-keying.
  sops.secrets."xray" = {
    format = "binary";
    sopsFile = ../../../secrets/mac_xray.conf;
  };

  # `xray` on PATH for manual inspection (`xray version`, `xray run -test`).
  home.packages = [ pkgs.xray ];

  launchd.agents.xray = {
    enable = true;
    config = {
      # The launcher blocks until sops-nix has written the decrypted config,
      # then exec's the real xray (see xrayLauncher above).
      ProgramArguments = [ "${xrayLauncher}" ];
      RunAtLoad = true;
      # Belt-and-suspenders: once the config is present, restart Xray if it
      # dies. The launcher already handles the boot race, so this no longer
      # carries the "start it in the first place" responsibility.
      KeepAlive.PathState.${xrayConfig} = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/xray.out.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/xray.err.log";
    };
  };
}
