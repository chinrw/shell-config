self: super: {
  buildRustPackage = super.buildRustPackage.overrideAttrs (oldAttrs: {
    postBuild = oldAttrs.postBuild or "" + ''
      export RUSTFLAGS="$RUSTFLAGS -C target-cpu=native -C link-arg=-fuse-ld=mold"
    '';
  });
}
