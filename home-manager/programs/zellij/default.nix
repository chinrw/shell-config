{ lib, pkgs, config, ... }: {

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

