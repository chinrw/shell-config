{
  config,
  hostname,
  ...
}:
{
  sops.secrets."cachix-agent-token" = {
    restartUnits = [ "cachix-agent.service" ];
  };

  services.cachix-agent = {
    enable = true;
    name = hostname;
    credentialsFile = config.sops.secrets."cachix-agent-token".path;
  };
}
