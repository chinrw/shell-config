{
  imports = [
    ../proxmox-lxc.nix
    ./proxy.nix
    ./postgresql.nix
    ./applications.nix
    ./lrr-image-update.nix
    ./runner.nix
  ];

  networking.nameservers = [ "127.0.0.1" ];
}
