{
  inputs,
  pkgs,
}:
{
  check-xray-version = pkgs.callPackage ./check-xray-version { };
}
