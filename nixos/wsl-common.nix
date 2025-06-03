{
  config,
  pkgs,
  hostname,
  username,
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

  sops = {
    age.keyFile = "/home/${username}/.config/sops/age/keys.txt"; # must have no password!
    # It's also possible to use a ssh key, but only when it has no password:
    #age.sshKeyPaths = [ "/home/user/path-to-ssh-key" ];
    defaultSopsFile = ../secrets/hosts.yaml;
    defaultSopsFormat = "yaml";

    secrets = {
      "wg/privatekey" = { };
      "wg/pubkey" = { };
      "ssh_pub_key" = { };
      "access-tokens" = { };
      "github-runners/midashood" = { };
    };
  };

  fileSystems."/mnt/autofs/data" = {
    device = "10.0.0.254:/volume1/Data";
    fsType = "nfs4";
    options = [
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=1h"
      "noatime"
      "_netdev"
    ];
  };
}
