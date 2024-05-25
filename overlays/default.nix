# This file defines overlays
{ inputs, ... }: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    eza = prev.eza.overrideAttrs (old: rec {
      # We can change the version of the package
      # pname = "eza";
      # version = "0.18.15";
      # src = prev.fetchFromGitHub {
      #   owner = "eza-community";
      #   repo = "eza";
      #   rev = "v${version}";
      #   hash = "sha256-8Kv2jDWb1HDjxeGZ36btQM/b+lx3yKkkvMxDyzmMUvw=";
      # };
      # cargoHash = "";
      # extraRustcOpts = "-C target-cpu=native";
    });
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
      config.allowUnfreePredicate = _: true;
    };
  };
}
