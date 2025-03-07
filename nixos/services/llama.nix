{ config, pkgs, ... }: {

  services = {
    ollama = {
      enable = true;
      package = pkgs.ollama;
      acceleration = "cuda";
      host = "0.0.0.0";
      environmentVariables = {
        http_proxy = "http://192.168.0.101:7891";
        https_proxy = "http://192.168.0.101:7891";
        LD_LIBRARY_PATH = "\${LD_LIBRARY_PATH}:/usr/lib/wsl/lib";
      };
    };
    open-webui = {
      enable = true;
      package = pkgs.unstable.open-webui;
      host = "192.168.0.201";
      environment = {
        http_proxy = "http://192.168.0.101:7891";
        https_proxy = "http://192.168.0.101:7891";
      };
    };
    # llama-cpp = {
    #   enable = true;
    #   host = "192.168.0.201";
    #   port = 8081;
    # };
  };
}
