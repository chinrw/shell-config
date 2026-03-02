# This file defines overlays
{ inputs, ... }:
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs final.pkgs;

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev:
    let
      isX86 = prev.stdenv.hostPlatform.isx86_64;

      # Optimized Clang stdenv with mold linker (x86_64-linux only).
      # Packages in clangOptimizedNames use this instead of the default GCC stdenv.
      optimizedClangStdenv =
        let
          # Use prev (not final) to avoid infinite recursion — packages built
          # with this stdenv must not pull in the overlay's own output.
          base = prev.llvmPackages.stdenv;
          llvmBins = prev.llvmPackages.llvm;
          moldBintools = base.cc.bintools.override (old: {
            extraBuildCommands = (old.extraBuildCommands or "") + ''
              ln -sf ${prev.mold}/bin/ld.mold $out/bin/ld.mold
            '';
          });
        in
        base.override {
          allowedRequisites = null;
          cc = base.cc.override (old: {
            bintools = moldBintools;
            extraBuildCommands = (old.extraBuildCommands or "") + ''
              echo "-O3 -march=x86-64-v3 -flto=thin -fno-plt -fno-semantic-interposition -ffunction-sections -fdata-sections -pipe -fuse-ld=mold -Wl,--gc-sections -Wl,--icf=safe -Wno-unused-command-line-argument" >> $out/nix-support/cc-cflags-before
              ln -sf ${llvmBins}/bin/llvm-ar $out/bin/ar
              ln -sf ${llvmBins}/bin/llvm-ranlib $out/bin/ranlib
              ln -sf ${llvmBins}/bin/llvm-nm $out/bin/nm
              ln -sf ${llvmBins}/bin/llvm-strip $out/bin/strip
            '';
          });
        };

      # Packages to build with optimized Clang + mold + cflags.
      clangOptimizedNames = [
        "htop"
        "fastfetch"
        "wget"
        "aria2"
        "mediainfo"
        "iperf3"
        "par2cmdline"
        "neovim"
        "zsh"
        "zsh-fzf-tab"
      ];
      clangOptimized =
        if isX86 then
          builtins.listToAttrs (
            map (name: {
              inherit name;
              value = prev.${name}.override { stdenv = optimizedClangStdenv; };
            }) clangOptimizedNames
          )
        else
          { };

      # GCC exception list — packages that fail to compile with Clang or LTO.
      gccExceptionNames = builtins.attrNames {
        # inherit (prev) packageName;
      };
      gccExceptions = builtins.listToAttrs (
        map (name: {
          inherit name;
          value = prev.${name}.override { stdenv = final.gccStdenv; };
        }) gccExceptionNames
      );

      # ── Rust optimization flags ────────────────────────────────────────
      optimizedRustFlags =
        (if isX86 then "-C target-cpu=x86-64-v3 " else "")
        + "-C link-arg=-fuse-ld=mold";

      # Rust packages to build with optimized flags.
      rustOptimizedNames = [
        "ripgrep"
        "fd"
        "bat"
        "zoxide"
        "dua"
        "tokei"
        "procs"
        "hexyl"
        "ouch"
        "tailspin"
        "hyperfine"
        "gitoxide"
        "binsider"
        "rustscan"
        "pyrefly"
      ];
      rustOptimized =
        if isX86 then
          builtins.listToAttrs (
            map (name: {
              inherit name;
              value = prev.${name}.overrideAttrs (old: {
                RUSTFLAGS = (old.RUSTFLAGS or "") + " ${optimizedRustFlags}";
                nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.mold ];
              });
            }) rustOptimizedNames
          )
        else
          { };
    in
    clangOptimized // gccExceptions // rustOptimized // {

    dstask = prev.dstask.overrideAttrs (old: {
      meta = old.meta // {
        platforms = final.lib.platforms.unix;
      };
    });

    # 7-Zip: unfree + uasm on x86_64 (uses GCC — its Makefile has GCC-specific flags)
    _7zz = prev._7zz.override {
      enableUnfree = true;
      useUasm = isX86;
    };

    # yazi: from flake input, uses shared Rust flags + optimized _7zz
    yazi =
      (inputs.yazi.packages.${prev.stdenv.hostPlatform.system}.default.override {
        _7zz = final._7zz;
      }).overrideAttrs
        (old: {
          extraRustcOpts = optimizedRustFlags;
        });
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-master {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
      config.allowUnfreePredicate = _: true;
    };
  };

  stable-packages = final: prev: {
    stable = import inputs.nixpkgs-stable {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
      config.allowUnfreePredicate = _: true;
    };
  };
}
