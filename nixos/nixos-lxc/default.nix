{ lib, ... }:
{
  imports = [
    ../proxmox-lxc.nix
    ./proxy.nix
    ./postgresql.nix
    ./applications.nix
    ./lanraragi.nix
    ./runner.nix
  ];

  systemd.services.docker.unitConfig.ConditionPathIsMountPoint = lib.mkForce [ ];

  networking.nameservers = [ "127.0.0.1" ];
}
