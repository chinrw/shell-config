{ pkgs, inputs, ... }:

let
  customKernel = import ./kernel-package.nix { inherit pkgs inputs; lib = pkgs.lib; };
in
{
  boot.kernelPackages = pkgs.linuxPackagesFor customKernel;
}