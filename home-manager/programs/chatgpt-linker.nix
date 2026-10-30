# ChatGPT reviews every task through vm-nix's connection, so vm-nix runs the
# tunnel and the task exchange. Other hosts keep the CLI and skill and publish
# to that exchange.
{
  config,
  hostname,
  lib,
  ...
}:
{
  config = lib.mkMerge [
    { programs.chatgpt-linker.enable = true; }
    (lib.mkIf (hostname == "vm-nix") {
      programs.chatgpt-linker = {
        tunnel = {
          enable = true;
          healthPort = 18473;
          tunnelId = "tunnel_6aaca9f6cf7481919f1dea0a634e5173";
          apiKeyFile = config.sops.secrets."chatgpt-linker/tunnel-api-key".path;
        };
        exchange = {
          enable = true;
          listen = "192.168.0.240";
          port = 8765;
          tokenFile = config.sops.secrets."chatgpt-linker/exchange-token".path;
          tlsCertFile = config.sops.secrets."chatgpt-linker/exchange-tls-cert".path;
          tlsKeyFile = config.sops.secrets."chatgpt-linker/exchange-tls-key".path;
        };
      };
      sops.secrets =
        lib.genAttrs
          [
            "chatgpt-linker/tunnel-api-key"
            "chatgpt-linker/exchange-token"
            "chatgpt-linker/exchange-tls-cert"
            "chatgpt-linker/exchange-tls-key"
          ]
          (_: {
            sopsFile = ../../secrets/hosts/vm-nix.yaml;
          });
      systemd.user.services.chatgpt-linker.Unit.After = [ "sops-nix.service" ];
      systemd.user.services.chatgpt-linker-exchange.Unit.After = [ "sops-nix.service" ];
    })
    (lib.mkIf (hostname == "nixos-lxc") {
      home.sessionVariables = {
        CHATGPT_LINKER_EXCHANGE_URL = "https://192.168.0.240:8765";
        CHATGPT_LINKER_EXCHANGE_TOKEN_FILE = "${config.xdg.configHome}/chatgpt-linker/exchange-token";
        CHATGPT_LINKER_EXCHANGE_CA_FILE = "${config.xdg.configHome}/chatgpt-linker/exchange-cert.pem";
      };
    })
  ];
}
