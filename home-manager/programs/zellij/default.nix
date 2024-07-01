{ lib, pkgs, config, ... }: {

  home.file."${config.xdg.configHome}/zellij" = {
    source = ../zellij;
    recursive = true;
  };
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

