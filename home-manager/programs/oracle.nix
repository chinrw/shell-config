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
    settings = {
      model = "gpt-6-astra";
      # Oracle 0.23.1 only knows GPT-6 Astra, and Chat still uses its picker entry.
      modelOverrides.gpt-6-astra.apiModel = "gpt-6.2-astra";
      reasoningMode = "pro";
      reasoningEffort = "high";
      browser = {
        modelStrategy = "select";
        thinkingTime = "pro";
        remoteChrome = {
          host = "192.168.0.240";
          port = 9522;
        };
        cookieSync = false;
      };
    };
  };
}
