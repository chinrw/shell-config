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
      enp6s18 = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = "192.168.0.240";
            prefixLength = 24;
          }
        ];
        dns = "192.168.0.1";
      };
    };
    defaultGateway = {
      address = "192.168.0.1";
      interface = "eth0";
    };
    hostName = hostname;
    networkmanager.enable = true;
    proxy.default = "http://192.168.0.101:7891";
  };

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
}
