# Xray client — macOS launchd user agent.
#
# NixOS hosts run Xray as a system service (`services.xray`, see
# nixos/vm-nix/default.nix). nix-darwin has no equivalent module, so on
# macOS we run the same pinned `pkgs.xray` (overlays/default.nix) as a
# per-user launchd agent that starts at login.
#
# Imported via programs/darwin/default.nix (macOS only).
{ config, pkgs, ... }:
let
  # Concrete on darwin, e.g. /Users/chin39/.config/sops-nix/secrets/xray.
  xrayConfig = config.sops.secrets."xray".path;
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
      ProgramArguments = [
        "${pkgs.xray}/bin/xray"
        "run"
        "-config"
        xrayConfig
        "-format"
        "json"
      ];
      RunAtLoad = true;
      # launchd has no systemd-style `After=`. Gating KeepAlive on the
      # decrypted config path makes launchd (re)launch Xray only once
      # sops-nix has written it, and restart it if it dies while present.
      KeepAlive.PathState.${xrayConfig} = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/xray.out.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/xray.err.log";
    };
  };
}
