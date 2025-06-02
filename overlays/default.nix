# This file defines overlays
{ inputs, ... }:
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    # eza = prev.eza.overrideAttrs (old: {
    #   # We can change the version of the package
    #   extraRustcOpts = "-C target-cpu=native -C link-arg=-fuse-ld=mold -Clinker-plugin-lto";
    # });
    # yazi = prev.yazi.overrideAttrs (old: {
    #   # We can change the version of the package
    #   extraRustcOpts = "-C target-cpu=native -C link-arg=-fuse-ld=mold -Clinker-plugin-lto";
    # });
    # zoxide = prev.zoxide.overrideAttrs (old: {
    #   # We can change the version of the package
    #   extraRustcOpts = "-C target-cpu=native -C link-arg=-fuse-ld=mold -Clinker-plugin-lto";
    # });
    # zellij = prev.zellij.overrideAttrs (old: rec {
    #   # We can change the version of the package
    #   extraRustcOpts = "-C target-cpu=native -C link-arg=-fuse-ld=mold -Clinker-plugin-lto";
    # });
    #
    # In Nix, the rec keyword stands for “recursive attribute set.” A recursive
    # set means that attributes defined inside can reference each other without
    # needing to be defined beforehand
    # rec {
    #   version = "0.26";
    #   src = fetchFromGitHub {
    #     owner = "naggie";
    #     repo  = "dstask";
    #     rev   = "v${version}";
    #     sha256 = "sha256-...";
    #   };
    # }
    # Without rec:
    # You can’t refer to attributes (like version) from within the same set; the
    # interpreter doesn’t know they exist yet.
    #
    # With rec: The set is self-referential. This means inside the set, you can
    # do things like rev = "v${version}" because version is also defined in
    # that same set.

    dstask = prev.dstask.overrideAttrs (old: {

      # Update the rev and sha256 accordingly
      # src = final.fetchurl {
      #   url = "https://github.com/naggie/dstask/archive/refs/tags/0.27.tar.gz";
      #   hash = "sha256-hdqS61DDYR4QVPUVPcDPkP4bixIhnHfRqoamE4TEUKA=";
      # };

      # Override the platforms
      meta = old.meta // {
        platforms = final.lib.platforms.unix;
      };
    });

    _7zz = prev._7zz.override (old: {
      enableUnfree = true;
      useUasm = true;
    });

    yazi = (inputs.yazi.packages.${final.system}.default.override {
      #NOTE need use final to use modify 7z
      _7zz = final._7zz;
    }).overrideAttrs (old: {
      # We can change the version of the package
      extraRustcOpts = "-C target-cpu=native -C link-arg=-fuse-ld=mold -Clinker-plugin-lto";
    });

    zsh-fzf-tab = prev.zsh-fzf-tab.override (old: {
      stdenv = final.clangStdenv;
    });

    buildRustPackage = prev.buildRustPackage.overrideAttrs (old: {
      postBuild =
        old.postBuild or ""
        + ''
          export RUSTFLAGS="$RUSTFLAGS -C target-cpu=native -C link-arg=-fuse-ld=mold"
        '';
    });
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-master {
      inherit (final) system;
      config.allowUnfree = true;
      config.allowUnfreePredicate = _: true;
    };
  };

  stable-packages = final: prev: {
    stable = import inputs.nixpkgs-stable {
      inherit (final) system;
      config.allowUnfree = true;
      config.allowUnfreePredicate = _: true;
    };
  };
}
