{ pkgs, inputs, ... }:

pkgs.mkShell {
  packages = [
    inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
    pkgs.git
  ];

  NIX_CONFIG = "experimental-features = nix-command flakes";
}
