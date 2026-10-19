{
  config,
  inputs,
  lib,
  username,
  ...
}:
# Telegram channels and groups for Hermes, served by github:chinrw/telegram-reader.
# The server runs on the host as its own user, so the account session never
# enters the Hermes container.
{
  imports = [ inputs.telegram-reader.nixosModules.default ];

  sops.secrets = lib.genAttrs [ "telegram-reader/api_id" "telegram-reader/api_hash" ] (_: {
    owner = "telegram-reader";
    mode = "0400";
    restartUnits = [ "telegram-reader.service" ];
  });

  services.telegram-reader = {
    enable = true;
    apiIdFile = config.sops.secrets."telegram-reader/api_id".path;
    apiHashFile = config.sops.secrets."telegram-reader/api_hash".path;
    # MTProto has no direct route out of this network. The xray HTTP inbound
    # carries it with CONNECT.
    proxy = config.networking.proxy.default;
    # The shared media tree, which the Hermes container mounts at the same path.
    downloads = {
      directory = "/mnt/data/Downloads/telegram";
      createAs = username;
    };
  };

  # The proxy above is xray, so start after it.
  systemd.services.telegram-reader = {
    wants = [ "xray.service" ];
    after = [ "xray.service" ];
  };
}
