{ config, inputs, ... }:
{
  imports = [ inputs.oracle-nix.homeManagerModules.default ];

  sops.secrets.openai-api-key = {
    sopsFile = ../../secrets/openai.yaml;
    key = "api_key";
  };

  programs.oracle = {
    enable = true;
    skills.enable = true;
    apiKeyFile = config.sops.secrets.openai-api-key.path;
  };
}
