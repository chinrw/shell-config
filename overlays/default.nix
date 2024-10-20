# This file defines overlays
{ inputs, ... }: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    eza = prev.eza.overrideAttrs (old: {
      # We can change the version of the package
      extraRustcOpts = "-C target-cpu=native -C link-arg=-fuse-ld=mold";
    });
    yazi = prev.yazi.overrideAttrs (old: {
      # We can change the version of the package
      extraRustcOpts = "-C target-cpu=native -C link-arg=-fuse-ld=mold";
    });
    zoxide = prev.zoxide.overrideAttrs (old: {
      # We can change the version of the package
      extraRustcOpts = "-C target-cpu=native -C link-arg=-fuse-ld=mold";
    });
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      inherit (final) system;
      config.allowUnfree = true;
      config.allowUnfreePredicate = _: true;
    };
  };
}
