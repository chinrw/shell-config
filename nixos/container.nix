{ config, pkgs, ... }: {

  environment.systemPackages = with pkgs; [
    nvidia-docker
  ];
  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
      daemon.settings = {
        features.cdi = true;
        cdi-spec-dirs = [ "/etc/cdi" ];
      };
    };
    daemon.settings = {
      features.cdi = true;
      cdi-spec-dirs = [ "/etc/cdi" ];
    };
  };
}
