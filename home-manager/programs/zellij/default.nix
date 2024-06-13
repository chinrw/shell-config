{ lib, pkgs, isDesktop, isLaptop, ... }: {

  programs.zellij = {


    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableFishIntegration = true;

    settings = "

    ";

  };
}

