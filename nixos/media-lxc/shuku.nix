{ config, inputs, ... }:
{
  imports = [ inputs.shuku.nixosModules.default ];

  # Some library directories require the users group. The module still mounts
  # the content directories read-only.
  users.users.shuku.extraGroups = [ "users" ];

  # Keep console settings in each database so restarts preserve UI changes.
  services.shuku = {
    enable = true;
    instances.doujinshi = {
      libraryDir = "/mnt/data/harmony/本子";
      dataDir = "/var/lib/shuku/doujinshi";
      listenAddress = "192.168.0.231";
      port = 3002;
      openFirewall = true;
      environment = config.networking.proxy.envVars;
    };
    instances.manga = {
      libraryDir = "/mnt/data/harmony/漫画";
      dataDir = "/var/lib/shuku/manga";
      listenAddress = "192.168.0.231";
      port = 3003;
      openFirewall = true;
      environment = config.networking.proxy.envVars;
    };
  };
}
