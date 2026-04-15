{
  config,
  lib,
  hostname,
  ...
}:
let
  enabledHosts = [
    "vm-nix"
    "proxmox"
  ];
  isEnabled = builtins.elem hostname enabledHosts;
in
{
  sops.secrets = lib.mkIf isEnabled {
    "syncthing-gui" = { };
  };

  services.syncthing = lib.mkIf isEnabled {
    enable = true;
    guiAddress = "0.0.0.0:8384";
    overrideFolders = false;

    guiCredentials = {
      username = "chin39";
      passwordFile = config.sops.secrets."syncthing-gui".path;
    };

    settings = lib.mkMerge [
      {
        options.urAccepted = -1;
      }
      (lib.mkIf (hostname == "proxmox") {
        devices.windows-desktop = {
          id = "XTINWEA-LVW3WH3-4L5P67N-S3NOKFI-I6LGIW7-SSDXS6Z-R67CYZU-NBJVAQ6";
          addresses = [ "tcp://192.168.0.101:22000" ];
          allowedNetworks = [ "192.168.0.0/24" ];
        };
        folders.onedrive = {
          path = "/mnt/elysion/data/Documents/onedrive";
          devices = [ "windows-desktop" ];
          type = "sendreceive";
          fsWatcherEnabled = true;
          fsWatcherDelayS = 10;
        };
      })
    ];
  };
}
