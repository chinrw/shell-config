{
  inputs,
  config,
  pkgs,
  hostname,
  ...
}:
{
  imports = [
    inputs.hardware.nixosModules.common-cpu-amd
    ./hardware.nix
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
    nameservers = [ "192.168.0.1" ];
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      10808
      10809
      12346
    ];
    # allowedUDPPortRanges = [
    #   { from = 4000; to = 4007; }
    #   { from = 8000; to = 8010; }
    # ];
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
}
