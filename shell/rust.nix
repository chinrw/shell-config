{ pkgs, ... }:

pkgs.mkShell {
  packages = with pkgs; [
    # rustToolchain
    (pkgs.rust-bin.beta.latest.default.override {
      extensions = [ "rust-src" ];
    })
    rust-analyzer

    nodePackages.cspell

    file
    jq
    poppler-utils
    unar
    ffmpegthumbnailer
    fd
    ripgrep
    fzf
    zoxide
    # keep this line if you use bash
    pkgs.bashInteractive
  ];

  # Temporarily disabled due to nixpkgs issue with darwin.apple_sdk_11_0
  # See: https://nixos.org/manual/nixpkgs/stable/#sec-darwin-legacy-frameworks
  # buildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin [
  #   pkgs.darwin.apple_sdk.frameworks.Foundation
  # ];

  env = {
    RUST_BACKTRACE = "1";
  };
}
