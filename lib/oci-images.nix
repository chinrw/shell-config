# Container images without a nixpkgs package are pinned by registry digest in
# oci-images.json, so a host runs exactly the image recorded in the repository.
# shell-config-updater refreshes the digests from their tags and pushes a
# refresh to main only after the Nix builds pass.
let
  images = builtins.fromJSON (builtins.readFile ./oci-images.json);
in
{
  ref =
    name:
    let
      image = images.${name} or (throw "lib/oci-images.json has no image named ${name}");
    in
    assert builtins.match "sha256:[0-9a-f]{64}" image.digest != null;
    "${image.repository}@${image.digest}";
}
