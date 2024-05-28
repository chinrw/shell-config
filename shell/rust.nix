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
    poppler_utils
    unar
    ffmpegthumbnailer
    fd
    ripgrep
    fzf
    zoxide
    # keep this line if you use bash
    pkgs.bashInteractive
  ];

  buildInputs = with pkgs;
    lib.optionals stdenv.isDarwin
      (with darwin.apple_sdk.frameworks; [ Foundation ]);

  env = { RUST_BACKTRACE = "1"; };
}
