{
  config,
  pkgs,
  hostname,
  ...
}:
{
  users.users.chin39 = {
    extraGroups = [
      "docker"
      "wheel"
    ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ config.sops.secrets.ssh_pub_key.path ];
  };

  wsl = {
    enable = true;
    defaultUser = "chin39";
    useWindowsDriver = true;
    wslConf.network = {
      # let linux handle hosts
      generateHosts = false;
      hostname = hostname;
    };
  };
}
