{
  config,
  ...
}:
{
  sops.secrets."nix-serve-secret-key" = {
    restartUnits = [ "nix-serve.service" ];
  };

  services.nix-serve = {
    enable = true;
    port = 5000;
    secretKeyFile = config.sops.secrets."nix-serve-secret-key".path;
  };

  networking.firewall.allowedTCPPorts = [ 5000 ];
}
