{
  inputs,
  hostname,
  pkgs,
  ...
}:
{
  imports = [
    inputs.hardware.nixosModules.common-pc-laptop
    inputs.hardware.nixosModules.common-pc-ssd
    ./desktop.nix
    ./storage.nix
  ];

  boot = {
    initrd.availableKernelModules = [
      "nvme"
      "sd_mod"
      "thunderbolt"
      "usb_storage"
      "usbhid"
      "xhci_pci"
    ];
    initrd.systemd.enable = true;
    kernelPackages = pkgs.linuxPackages_7_1;
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.enable = true;
    };
  };

  networking = {
    hostName = hostname;
    networkmanager.enable = true;
  };

  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };
    enableRedistributableFirmware = true;
    graphics.enable = true;
    cpu = {
      amd.updateMicrocode = true;
      intel.updateMicrocode = true;
    };
  };

  services = {
    fwupd.enable = true;
    pipewire = {
      alsa.enable = true;
      pulse.enable = true;
    };
  };

  security = {
    rtkit.enable = true;
    sudo.wheelNeedsPassword = true;
  };

  users = {
    # Preserve passwords set locally with passwd across rebuilds.
    mutableUsers = true;
    users.chin39 = {
      isNormalUser = true;
      description = "chin39";
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
    };
  };

  environment.systemPackages = [ pkgs.vim ];

  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";

}
