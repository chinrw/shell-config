{ pkgs, ... }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    home-manager
    git
  ];
  NIX_CONFIG = "experimental-features = nix-command flakes";
}
