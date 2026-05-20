{ ... }:
{
  # nix-darwin's built-in homebrew module talks to the existing /opt/homebrew
  # install; it does not bootstrap brew itself.
  homebrew = {
    enable = true;

    onActivation = {
      # Keep "none" for now so an unexpected delta does not vaporize apps.
      # Switch to "zap" once the declarative list is trusted to match reality.
      cleanup = "uninstall";
      autoUpdate = true;
      upgrade = true;
    };

    global = {
      brewfile = true;
    };

    taps = [
      "1password/tap"
      "apple/apple"
      "fsouza/prettierd"
      "playcover/playcover"
    ];

    # Formulae kept on brew because they are missing / awkward on darwin in
    # nixpkgs. Everything else lives in ./system-packages.nix.
    brews = [
      "bpython"
      "carthage"
      "latexindent"
      "luacheck"
      # samba on nixpkgs aarch64-darwin fails its bundled tests; the brew
      # bottle is the path of least resistance.
      "samba"
      "zsync"
    ];

    # GUI apps. Nerd Fonts + Lato come from nixpkgs `fonts.packages`
    # (see configuration.nix), so the brew font casks are intentionally
    # dropped.
    casks = [
      "1password"
      "1password-cli"
      "adobe-acrobat-pro"
      "android-file-transfer"
      "discord"
      "docker-desktop"
      "firefox"
      "google-chrome"
      "iina"
      "jellyfin-media-player"
      "jetbrains-toolbox"
      "keka"
      "mactex"
      "miniconda"
      "mono-mdk-for-visual-studio"
      "obs"
      "obsidian"
      "onedrive"
      "scroll-reverser"
      "skim"
      "steam"
      "sublime-text"
      "telegram"
      "thunderbird"
      "utm"
      "visual-studio-code"
      "vnc-viewer"
      "wezterm@nightly"
      "wireshark-app"
      "zed@preview"
      "zoom"
    ];

    # No Mac App Store apps in the brew dump — leave masApps empty.
    masApps = { };
  };
}
