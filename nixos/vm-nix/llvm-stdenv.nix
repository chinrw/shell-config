# Kernel toolchain, shared by kernel-package.nix and shell/kernel.nix so the
# real build and the interactive shell cannot drift apart.
#
# nixpkgs' clangStdenv pairs clang with GNU binutils, and the kernel builder's
# common-flags.nix derives every tool from stdenv.cc / stdenv.cc.bintools. That
# yields LD=GNU ld and a GNU AR/NM, so HAS_LTO_CLANG - which wants LD_IS_LLD
# plus an AR and NM whose --help says "llvm" - stays false and oldconfig
# silently drops the LTO_CLANG_* lines from kernel.config. It breaks the host
# side too: since 7.2 the kernel appends -fuse-ld=lld to KBUILD_HOSTLDFLAGS
# whenever LLVM is set, and clang on GNU bintools rejects that flag outright.
{ pkgs }:
let
  llvm = pkgs.llvmPinned;
in
pkgs.overrideCC pkgs.clangStdenv (llvm.clang.override { bintools = llvm.bintools; })
