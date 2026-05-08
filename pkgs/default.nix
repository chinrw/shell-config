# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  check-xray-version = pkgs.callPackage ./check-xray-version { };
}
