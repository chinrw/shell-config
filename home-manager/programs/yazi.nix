{
  inputs,
  pkgs,
  ...
}:
let
  # home-manager wants the plugin directory itself; the input holds one dir per plugin.
  gitPlugin = pkgs.runCommandLocal "git.yazi" { } ''
    cp -r ${inputs.yazi-plugin-git}/git.yazi $out
  '';
in
{
  programs.yazi = {
    enable = true;

    # No `y` wrapper functions: the shell config already handles yazi's arguments.
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableNushellIntegration = false;
    enableZshIntegration = false;

    # Silences home-manager's 26.05 rename warning; unused while integrations are off.
    shellWrapperName = "yy";

    plugins = {
      git = {
        package = gitPlugin;
        setup = true;
      };

      chmod.package = "${inputs.yazi-plugin-git}/chmod.yazi";

      # Only invoked from keymap.toml; it needs no setup call.
      time-travel.package = inputs.yazi-plugin-time-travel;
    };
  };

  # yazi.toml and keymap.toml stay hand-written in this repo.
  xdg.configFile = {
    "yazi/yazi.toml".source = ../../yazi/yazi.toml;
    "yazi/keymap.toml".source = ../../yazi/keymap.toml;
  };
}
