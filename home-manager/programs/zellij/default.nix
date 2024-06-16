{ lib, pkgs, ... }: {

  programs.zellij = {


    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableFishIntegration = true;

    # settings = "
    #   ";

  };
}

