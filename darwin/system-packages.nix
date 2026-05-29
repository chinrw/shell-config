{ pkgs, ... }:
{
  # System-wide CLI tools mirrored from the full Brewfile dump
  # (brew bundle dump --file=-). One-to-one with the brew install except
  # for the handful kept on Homebrew in ./homebrew.nix, namely:
  #   bpython, carthage, latexindent, luacheck, zsync
  environment.systemPackages = with pkgs; [
    # Shells
    bashInteractive
    zsh

    # Build / toolchain
    cmake
    coreutils
    gcc
    gnumake
    llvm
    nodejs
    openjdk
    pkg-config

    # Languages / runtimes — python is wrapped so `numpy` and `certifi`
    # (brew leaves) are importable from the system python. `torch` was
    # only here to back `openai-whisper`; both removed since whisper is no
    # longer needed.
    opam
    (python312.withPackages (
      ps: with ps; [
        certifi
        numpy
      ]
    ))

    # Dev tools
    cloc
    codex
    cscope
    git
    rust-analyzer
    shellcheck
    stylua
    swiftlint

    # Linters / formatters
    markdownlint-cli
    prettier
    prettierd
    vale

    # Media / docs deps
    ffmpeg
    poppler

    # Net / sysadmin
    # NOTE: `samba` is kept on Homebrew in ./homebrew.nix because the
    # nixpkgs aarch64-darwin build of samba 4.23 fails its bundled
    # ldb tests under clang. Brew ships a working bottle.
    iperf3
    nmap
    proxychains-ng
    smartmontools
    socat
    tailscale
    usbutils
    wget
    wireguard-tools

    # Virtualisation
    qemu
    swtpm
    minikube

    # Misc utilities from brew leaves
    cdrtools
    genact
    gource
    jq
    miller
    qrencode
    rename
    rnr
  ];
}
