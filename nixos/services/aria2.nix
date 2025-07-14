{ config, pkgs, username, ... }:
{
  sops = {
    age.keyFile = "/home/${username}/.config/sops/age/keys.txt"; # must have no password!
    defaultSopsFile = ../../secrets/hosts.yaml;
    defaultSopsFormat = "yaml";

    secrets = {
      "aria2-token" = { };
    };
  };
  services.aria2 = {
    enable = true;
    rpcSecretFile = config.sops.secrets."aria2-token".path;
    openPorts = true;

    settings = {
      dir = "/mnt/elysion/data/Downloads/aria2";
      enable-rpc = true;
      "disable-ipv6" = true;
      "rpc-listen-all" = true;
      "rpc-allow-origin-all" = true;
      "auto-file-renaming" = false;
      "max-concurrent-downloads" = 10;
    };
  };
}

