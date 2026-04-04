{
  lib,
  hostname,
  ...
}:
let
  enabledHosts = [
    "vm-nix"
  ];
in
{
  services.syncthing = lib.mkIf (builtins.elem hostname enabledHosts) {
    enable = true;
  };
}
