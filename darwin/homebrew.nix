{ lib, pkgs, ... }:
let
  # Same local proxy the nix-daemon uses (see ./nix-daemon-proxy.nix).
  proxyURL = "http://127.0.0.1:10809";
  # The proxy occasionally terminates long HTTP/2 downloads with curl error
  # 92. Keep Homebrew downloads on HTTP/1.1 and retry transient transfer
  # failures; HOMEBREW_CURLRC makes Homebrew pass this file to curl explicitly.
  homebrewCurlrc = pkgs.writeText "homebrew-curlrc" ''
    http1.1
    retry-all-errors
  '';
in
{
  # nix-darwin's built-in homebrew module talks to the existing /opt/homebrew
  # install; it does not bootstrap brew itself.
  homebrew = {
    enable = true;

    # force to update the cask bundles
    greedyCasks = true;

    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = false;
      # Homebrew 5.1+ refuses `brew bundle --cleanup` unless one of --force,
      # --force-cleanup or $HOMEBREW_ASK is given. nix-darwin doesn't pass one,
      # so add it here. --force-cleanup runs the zap cleanup non-interactively
      # and, unlike --force, doesn't also imply install --overwrite.
      extraFlags = [ "--force-cleanup" ];
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
      # Opt out of greedy
      {
        name = "docker-desktop";
        greedy = false;
      }
      "firefox"
      "google-chrome"
      "iina"
      "jellyfin-media-player"
      "jetbrains-toolbox"
      "keka"
      "mactex"
      "miniconda"
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
      # Opt out of greedy
      {
        name = "wezterm@nightly";
        greedy = false;
      }
      "wireshark-app"
      "zed@preview"
      "zoom"
    ];

    # No Mac App Store apps in the brew dump — leave masApps empty.
    masApps = { };
  };

  # The nix-darwin homebrew activation runs `brew bundle` during
  # `darwin-rebuild switch` as the desktop user via sudo. Homebrew uses curl's
  # standard lowercase proxy variables; HOMEBREW_HTTP_PROXY and
  # HOMEBREW_HTTPS_PROXY are not supported Homebrew settings.
  #
  # Keep the variables scoped to activation, then allow sudo to pass them to
  # the `brew bundle` process. Interactive brew already gets its proxy from the
  # zsh session (see home-manager/programs/zsh).
  security.sudo.extraConfig = ''
    Defaults:root env_keep += "http_proxy https_proxy HOMEBREW_CURLRC"
  '';

  system.activationScripts.homebrew.text = lib.mkBefore ''
    export http_proxy="${proxyURL}"
    export https_proxy="${proxyURL}"
    export HOMEBREW_CURLRC="${homebrewCurlrc}"
  '';
}
