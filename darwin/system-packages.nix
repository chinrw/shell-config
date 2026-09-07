{ pkgs, ... }:
let
  # Full TeX toolchains belong to project flakes; expose only the formatter.
  latexindent = pkgs.writeShellScriptBin "latexindent" ''
    exec ${pkgs.texlive.withPackages (ps: [ ps.latexindent ])}/bin/latexindent "$@"
  '';
in
{
  # bpython, carthage and samba remain on Homebrew; see ./homebrew.nix.
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
    # NOTE: `codex` is installed per-user from the codex-cli-nix flake in
    # home-manager/home.nix, so it is deliberately absent here.
    cloc
    cscope
    git
    rust-analyzer
    shellcheck
    stylua
    swiftlint

    # Linters / formatters
    luaPackages.luacheck
    markdownlint-cli
    prettier
    prettierd
    latexindent
    vale

    # Media / docs deps
    ffmpeg
    libtiff
    libwebp
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
    zsync

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
