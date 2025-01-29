{ config, pkgs, ... }: {


  hardware = {
    nvidia-container-toolkit = {
      enable = true;
      mount-nvidia-executables = true;
    };
    nvidia = {
      modesetting.enable = true;
      nvidiaSettings = false;
      open = false;
    };
  };
  services.xserver.videoDrivers = [ "nvidia" ];
}
