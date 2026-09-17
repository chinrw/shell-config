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

      augment-command = {
        package = inputs.yazi-plugin-augment-command;
        setup = true;
        settings = {
          prompt = false;
          default_item_group_for_prompt = "hovered";
          smart_enter = true;
          smart_paste = false;
          enter_archives = true;
          extract_retries = 1;
          must_have_hovered_item = true;
          skip_single_subdirectory_on_enter = true;
          skip_single_subdirectory_on_leave = true;
          wraparound_file_navigation = false;
        };
      };

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
