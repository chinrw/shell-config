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

      8080 # open-webui
      # kik
      8888

      8096
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
  };
}
