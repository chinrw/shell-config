{
  inputs,
  config,
  pkgs,
  hostname,
  username,
  ...
}:
{
  imports = [
    inputs.hardware.nixosModules.common-cpu-amd
    ./hardware.nix
    ./wireguard.nix
    ./container/jellyfin.nix
    ../services/github-runners.nix
    ../services/samba/wsl-server.nix
    ../services/aria2.nix
    ../services/qbittorrent.nix
    ./rclone.nix
    # ./proxy.nix
  ];

  users.users.chin39 = {
    isNormalUser = true;
    description = "chin39";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    shell = pkgs.zsh;
    packages = with pkgs; [ ];
  };

  networking = {
    interfaces = {
      ens18 = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "192.168.0.240";
            prefixLength = 24;
          }
        ];
      };
    };
    defaultGateway = {
      address = "192.168.0.1";
      interface = "ens18";
    };
    hostName = hostname;
    networkmanager.enable = true;
    proxy.default = "http://192.168.0.240:10809";
    proxy.noProxy = "10.0.0.0/24,192.168.0.0/24,127.0.0.1,localhost,.localdomain";
    nameservers = [ "192.168.0.1" ];
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [

      # Alist firewall port
      5244
      5246
      5432

      5000 # kavita
      3001 # lanraragi
      7892 # AutoBangumi

      8080 # open-webui
      8888 # kik

      8096 # jellyfin
      7359
      1900

      10808
      10809
    ];
    allowedUDPPorts = [
      53
    ];
    allowedUDPPortRanges = [
      # { from = 4000; to = 4007; }
      # { from = 8000; to = 8010; }
    ];
  };

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Set your time zone.
  time.timeZone = "Asia/Shanghai";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "C.UTF-8";
    LC_IDENTIFICATION = "C.UTF-8";
    LC_MEASUREMENT = "C.UTF-8";
    LC_MONETARY = "C.UTF-8";
    LC_NAME = "C.UTF-8";
    LC_NUMERIC = "C.UTF-8";
    LC_PAPER = "C.UTF-8";
    LC_TELEPHONE = "C.UTF-8";
    LC_TIME = "C.UTF-8";
  };

  sops = {
    age.keyFile = "/home/${username}/.config/sops/age/keys.txt"; # must have no password!
    # It's also possible to use a ssh key, but only when it has no password:
    #age.sshKeyPaths = [ "/home/user/path-to-ssh-key" ];
    defaultSopsFile = ../../secrets/hosts.yaml;
    defaultSopsFormat = "yaml";

    secrets = {
      "wg-vm-nix/privatekey" = { };
      "ssh_pub_key" = { };
      "access-tokens" = { };
      "github-runners/Constantinople" = { };
      "smb_creds" = { };
    };
  };

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };
  sops.secrets."xray" = {
    owner = "root";
    sopsFile = ../../secrets/xray.conf;
    path = "/etc/xray/xray_client.conf";
    format = "binary";
  };

  services.xray = {
    enable = true;
    settingsFile = "/etc/xray/xray_client.conf";
  };

  services = {
    qemuGuest.enable = true;
    adguardhome = {
      enable = true;
      openFirewall = true;
      settings = {
        http_proxy = "http://127.0.0.1:10809";
      };
    };
    open-webui = {
      enable = true;
      package = pkgs.unstable.open-webui;
      host = "192.168.0.240";
      environment = {
        http_proxy = "http://192.168.0.240:10809";
        https_proxy = "http://192.168.0.240:10809";
      };
    };

    kavita = {
      enable = true;
      tokenKeyFile = "/etc/nixos/secrets/kavita_token.key";
      # make sure the service user can read the key
    };
    komga = {
      enable = true;
      openFirewall = true;
      settings.server.port = 8081;
    };
    # lanraragi = {
    #   enable = true;
    #   package = pkgs.lanraragi;
    #   port = 3001;
    # };

  };
  users.users.kavita.extraGroups = [ "kavita" ];

  environment.systemPackages = with pkgs; [
    cifs-utils
  ];

  fileSystems."/mnt/data" = {
    device = "//192.168.0.254/data"; # UNC path
    fsType = "cifs";
    options = [
      "vers=3.11"
      "credentials=${config.sops.secrets."smb_creds".path}"
      "multichannel,max_channels=4"
      "cache=loose,actimeo=30"
      "rsize=130048,wsize=57344"
      "fsc"
      "uid=1000"
      "gid=100"
      "iocharset=utf8"
      "_netdev" # delays mount until network-online.target
      "x-systemd.automount" # lazy-mount on first access
    ];
    neededForBoot = false;
  };

  fileSystems."/mnt/autofs/data" = {
    device = "10.0.0.254:/volume1/Data";
    fsType = "nfs4";
    options = [
      "noauto"
      "x-systemd.requires=wireguard-wg0-peer-arch-synology-refresh.service"
      "x-systemd.after=wireguard-wg0-peer-arch-synology-refresh.service"
      "noatime"
      "nofail"
      "_netdev"
      "x-systemd.automount"
    ];
    neededForBoot = false;
  };

  systemd.services.lanraragi.environment = {
    http_proxy = "http://192.168.0.254:10809";
    https_proxy = "http://192.168.0.254:10809";
  };

}
