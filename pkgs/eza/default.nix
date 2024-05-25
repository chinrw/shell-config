{ pkgs ? import <nixpkgs> {} }:

let
  # Import the custom package
  eza = pkgs.callPackage ./eza.nix { };
in
  {
    # Add custom packages to the environment
    customPackages = {
      inherit eza;
    };

    # Define a development shell (optional)
    shell = pkgs.mkShell {
      buildInputs = [
        eza
      ];
    };
  }
