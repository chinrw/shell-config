{ pkgs, inputs, ... }:

let
  kernelPkg = import ../nixos/vm-nix/kernel-package.nix { inherit pkgs inputs; lib = pkgs.lib; };
in
pkgs.mkShell.override { stdenv = pkgs.clangStdenv; } {
  name = "kernel-dev-shell";
  
  # Automatically pull in all build inputs (bison, flex, openssl, etc.) from the actual kernel package
  inputsFrom = [ kernelPkg ];

  # Add extra tools for interactive development that aren't strictly build deps
  packages = with pkgs; [
    ncurses # for menuconfig
    pkg-config
    python3
    lld
    kmod
  ];

  # Re-export necessary variables
  KERNEL_SRC = kernelPkg.src;
  KERNEL_VERSION = kernelPkg.version;
  LLVM = "1";

  shellHook = ''
    echo "Kernel Source: $KERNEL_SRC"
    echo "Kernel Version: $KERNEL_VERSION"
    echo "Environment synchronized with system kernel build."
    
    # Function to setup a writable workdir
    setup_workdir() {
      echo "Setting up writable kernel workspace..."
      rm -rf ./kernel-build
      cp -r $KERNEL_SRC ./kernel-build
      chmod -R u+w ./kernel-build
      cd ./kernel-build
      
      if [ -f ../nixos/vm-nix/kernel.config ]; then
        echo "Copying existing config..."
        cp ../nixos/vm-nix/kernel.config .config
      else 
        echo "No existing config found at ../nixos/vm-nix/kernel.config"
      fi
    }

    echo "Run 'setup_workdir' to copy sources to ./kernel-build and start working."
  '';
}