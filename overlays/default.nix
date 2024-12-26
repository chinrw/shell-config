# This file defines overlays
{ inputs, ... }: {
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

    awscli2 = prev.awscli2.overrideAttrs (old: {
      # We can change the version of the package
      postPatch = ''
        substituteInPlace pyproject.toml \
          --replace-fail 'flit_core>=3.7.1,<3.9.1' 'flit_core>=3.7.1' \
          --replace-fail 'awscrt>=0.19.18,<=0.22.0' 'awscrt>=0.22.0' \
          --replace-fail 'cryptography>=40.0.0,<43.0.2' 'cryptography>=43.0.0' \
          --replace-fail 'distro>=1.5.0,<1.9.0' 'distro>=1.5.0' \
          --replace-fail 'docutils>=0.10,<0.20' 'docutils>=0.10' \
          --replace-fail 'prompt-toolkit>=3.0.24,<3.0.39' 'prompt-toolkit>=3.0.24'

        substituteInPlace requirements-base.txt \
          --replace-fail "wheel==0.43.0" "wheel>=0.43.0"

        # Upstream needs pip to build and install dependencies and validates this
        # with a configure script, but we don't as we provide all of the packages
        # through PYTHONPATH
        sed -i '/pip>=/d' requirements/bootstrap.txt
      '';
    });

    zsh-fzf-tab = prev.zsh-fzf-tab.override (old: {
      stdenv = final.clangStdenv;
    });


    buildRustPackage = prev.buildRustPackage.overrideAttrs (old: {
      postBuild = old.postBuild or "" + ''
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
}
