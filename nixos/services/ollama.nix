{ config, pkgs, ... }: {
  services = {
    ollama = {
      enable = true;
      package = pkgs.ollama;
      acceleration = "cuda";
      host = "192.168.0.201";
      environmentVariables = {
        LD_LIBRARY_PATH = "\${LD_LIBRARY_PATH}:/usr/lib/wsl/lib";
      };
    };
    open-webui = {
      enable = true;
      package = pkgs.open-webui;
      host = "192.168.0.201";
    };
  };
}
