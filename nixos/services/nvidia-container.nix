{ config, pkgs, ... }: {

  environment.systemPackages = with pkgs; [
    nvidia-docker
  ];
  virtualisation.docker = {
    rootless = {
      daemon.settings = {
        cdi-spec-dirs = [ "/etc/cdi" ];
      };
    };
    daemon.settings = {
      cdi-spec-dirs = [ "/etc/cdi" ];
    };
  };
}
