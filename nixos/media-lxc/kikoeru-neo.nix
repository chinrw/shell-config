{ config, inputs, ... }:
let
  port = 8888;
in
{
  imports = [ inputs.kikoeru-neo.nixosModules.default ];

  services.kikoeru-neo = {
    enable = true;
    settings = {
      listen = "0.0.0.0:${toString port}";
      public_url = "https://kikoeru.home.midashood.top";
      trusted_proxies = [ "127.0.0.1" ];
      metadata.fallback = "asmr_one";
    };
  };

  systemd.services.kikoeru-neo.environment = {
    HTTPS_PROXY = config.networking.proxy.default;
    NO_PROXY = config.networking.proxy.noProxy;
  };

  networking.firewall.allowedTCPPorts = [ port ];
}
