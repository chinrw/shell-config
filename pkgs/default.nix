{
  inputs,
  pkgs,
}:
{
  check-xray-version = pkgs.callPackage ./check-xray-version { };
  deploy-rs-ci = pkgs.writeShellScriptBin "deploy-rs-ci" ''
    # Nix's daemon needs an explicit identity and host key for the shared builder.
    # Scope this policy to deployment checks and builds, leaving other Nix commands alone.
    export NIX_CONFIG="''${NIX_CONFIG-}
    builders = ssh-ng://chin39@192.168.0.230 x86_64-linux $HOME/.ssh/id_ed25519 1 1 benchmark,big-parallel,kvm,nixos-test - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU1lRmNmd09mN29XN3BVcTRPcmJISHkrS0lFTVN6bVdBSXVyY1ZMcndHVFA=
    builders-use-substitutes = true
    max-jobs = 0
    cores = 2
    "
    exec ${pkgs.lib.getExe inputs.deploy-rs.packages.${pkgs.stdenv.hostPlatform.system}.default} "$@"
  '';
}
