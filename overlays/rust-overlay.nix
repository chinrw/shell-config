self: super: {
  rustPlatform = super.rustPlatform.override {
    buildRustPackage = super.rustPlatform.buildRustPackage.overrideAttrs (oldAttrs: {
      postBuild = oldAttrs.postBuild or "" + ''
        export RUSTFLAGS="$RUSTFLAGS -C target-cpu=native"
      '';
    });
  };
}

