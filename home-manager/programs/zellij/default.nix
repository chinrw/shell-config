{
  lib,
  pkgs,
  config,
  ...
}:
let
  # zellij's cache dir: XDG on Linux, reverse-DNS bundle dir on darwin.
  # Writing ~/.cache/zellij on a Mac is a silent no-op.
  zellijCacheDir =
    if pkgs.stdenv.isDarwin then
      "${config.home.homeDirectory}/Library/Caches/org.Zellij-Contributors.Zellij"
    else
      "${config.xdg.cacheHome}/zellij";
in
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

  # zj-sysinfo is paneless, so it can never answer zellij's permission
  # prompt; without a pre-seeded grant the widgets stay blank. Replace rather
  # than append-if-missing: zellij auto-grants only when the cached entry
  # covers everything requested, so a stale entry re-prompts invisibly.
  # Other entries, which zellij owns and rewrites, pass through untouched.
  # Running sessions keep their in-memory permissions until restarted.
  home.activation.zjSysinfoPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ZELLIJ_CACHE_DIR="${zellijCacheDir}"
    ZELLIJ_PERMISSIONS="$ZELLIJ_CACHE_DIR/permissions.kdl"
    ZJ_SYSINFO_PLUGIN_PATH="${config.xdg.configHome}/zellij-plugins/zj-sysinfo.wasm"

    run ${pkgs.coreutils}/bin/mkdir -p "$ZELLIJ_CACHE_DIR"

    {
      # Drop our own block. permissions.kdl blocks are flat, so matching the
      # quoted path and skipping to the next `}` is enough.
      if [ -f "$ZELLIJ_PERMISSIONS" ]; then
        ${pkgs.gawk}/bin/awk -v target="$ZJ_SYSINFO_PLUGIN_PATH" '
          {
              line = $0
              sub(/^[ \t]+/, "", line)
              sub(/[ \t]+$/, "", line)
              if (skip) {
                  if (line == "}") { skip = 0 }
                  next
              }
              if (line == "\"" target "\" {") { skip = 1; next }
              print
          }
        ' "$ZELLIJ_PERMISSIONS"
      fi
      ${pkgs.coreutils}/bin/cat <<EOF
"$ZJ_SYSINFO_PLUGIN_PATH" {
    FullHdAccess
    MessageAndLaunchOtherPlugins
    RunCommands
}
EOF
    } > "$ZELLIJ_PERMISSIONS.hm-new"

    run ${pkgs.coreutils}/bin/mv -f "$ZELLIJ_PERMISSIONS.hm-new" "$ZELLIJ_PERMISSIONS"
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
