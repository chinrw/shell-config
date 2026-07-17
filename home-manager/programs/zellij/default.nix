{
  lib,
  pkgs,
  config,
  ...
}:
{

  home.file = {
    "${config.xdg.configHome}/zellij" = {
      source = ../../../zellij;
      recursive = true;
    };
    "${config.xdg.configHome}/zellij-plugins/zjstatus.wasm" = {
      source = "${pkgs.zjstatus}/bin/zjstatus.wasm";
    };
    "${config.xdg.configHome}/zellij-plugins/zjframes.wasm" = {
      source = "${pkgs.zjstatus}/bin/zjframes.wasm";
    };
    "${config.xdg.configHome}/zellij-plugins/zj-sysinfo.wasm" = {
      source = "${pkgs.zj-sysinfo}/bin/zj-sysinfo.wasm";
    };
  };

  # zj-sysinfo is a background (paneless) plugin, so it can never show the
  # interactive FullHdAccess/MessageAndLaunchOtherPlugins permission prompt
  # (zellij has nowhere to render it). Without a pre-seeded grant the
  # widgets just stay silently blank forever. Seed the grant into zellij's
  # own permission cache on every switch, keyed by the stable
  # zj-sysinfo.wasm symlink path above. Idempotent by construction: only
  # appends when the entry is absent, and never rewrites the rest of the
  # file, since zellij owns and rewrites permissions.kdl itself at runtime.
  home.activation.zjSysinfoPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ZELLIJ_CACHE_DIR="${config.xdg.cacheHome}/zellij"
    ZELLIJ_PERMISSIONS="$ZELLIJ_CACHE_DIR/permissions.kdl"
    ZJ_SYSINFO_PLUGIN_PATH="${config.xdg.configHome}/zellij-plugins/zj-sysinfo.wasm"

    run ${pkgs.coreutils}/bin/mkdir -p "$ZELLIJ_CACHE_DIR"

    if [ ! -f "$ZELLIJ_PERMISSIONS" ] || \
       ! ${pkgs.gnugrep}/bin/grep -F -q "$ZJ_SYSINFO_PLUGIN_PATH" "$ZELLIJ_PERMISSIONS"; then
      ${pkgs.coreutils}/bin/cat >> "$ZELLIJ_PERMISSIONS" <<EOF
"$ZJ_SYSINFO_PLUGIN_PATH" {
    FullHdAccess
    MessageAndLaunchOtherPlugins
}
EOF
    fi
  '';

  # programs.zellij = {
  #
  #
  #   enable = true;
  #   enableBashIntegration = true;
  #   enableZshIntegration = true;
  #   enableFishIntegration = true;
  #
  #   # settings = "
  #   #   ";
  #
  # };
}
