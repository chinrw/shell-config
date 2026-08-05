{
  inputs,
  pkgs,
}:
{
  check-xray-version = pkgs.callPackage ./check-xray-version { };
  oh-my-pi = pkgs.callPackage ./oh-my-pi { inherit inputs pkgs; };
}
