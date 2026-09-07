{ lib, hermesInput }:
let
  source = builtins.readFile "${hermesInput}/nix/nixosModules.nix";
  oldCommand = "gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg";
  # A restart before the provisioned marker leaves this public key in place.
  # GPG must overwrite it without asking for a terminal on the next start.
  patched =
    assert builtins.length (lib.splitString oldCommand source) == 2;
    builtins.replaceStrings
      [ oldCommand "import ./moduleCommon.nix" ]
      [
        "gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg"
        "import ${hermesInput}/nix/moduleCommon.nix"
      ]
      source;
  module = builtins.toFile "hermes-nixos-provisioning.nix" patched;
in
(import module {
  inputs = hermesInput.inputs // {
    self = hermesInput;
  };
}).flake.nixosModules.default
