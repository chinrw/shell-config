{ pkgs, lib, inputs, ... }:

let
  kernelSrc = inputs.linux-src;

  # Helper to extract version variables from Makefile
  makefile = builtins.readFile "${kernelSrc}/Makefile";
  
  getMakeVar = name:
    let
      lines = lib.splitString "\n" makefile;
      line = lib.findFirst (l: builtins.match "^${name} = .*" l != null) null lines;
    in
      if line == null then "" 
      else 
        let m = builtins.match "^${name} = *([^ ]+).*" line;
        in if m == null then "" else builtins.head m;

  version = "${getMakeVar "VERSION"}.${getMakeVar "PATCHLEVEL"}.${getMakeVar "SUBLEVEL"}";
  extra = getMakeVar "EXTRAVERSION";
  fullVersion = if extra != "" then "${version}${extra}" else version;

in
pkgs.linuxManualConfig {
  version = "${fullVersion}-rolling";
  modDirVersion = fullVersion;

  src = kernelSrc;

  configfile = ./kernel.config;

  # Enable LLVM build
  stdenv = pkgs.clangStdenv;
  extraMakeFlags = [ "LLVM=1" ];
}
