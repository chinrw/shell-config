{ lib, ... }:
let
  # Same local proxy the nix-daemon uses (see ./nix-daemon-proxy.nix).
  proxyURL = "http://127.0.0.1:10809";
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
      upgrade = true;
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

  # Route Homebrew through the local proxy.
  #
  # Interactive `brew` already inherits http_proxy/https_proxy from the zsh
  # session (see home-manager/programs/zsh), but set the Homebrew-specific
  # variants too: they survive brew's environment sanitization and make the
  # intent explicit for login shells.
  environment.variables = {
    HOMEBREW_HTTP_PROXY = proxyURL;
    HOMEBREW_HTTPS_PROXY = proxyURL;
  };

  # The nix-darwin homebrew activation runs `brew bundle` during
  # `darwin-rebuild switch` with a sanitized environment (sudo strips the
  # caller's http_proxy), so the auto-update / upgrade / bundle would otherwise
  # bypass the proxy. Export it right before the bundle command runs — mkBefore
  # prepends into the same activation shell as the module's `brew bundle` line.
  system.activationScripts.homebrew.text = lib.mkBefore ''
    export HOMEBREW_HTTP_PROXY="${proxyURL}"
    export HOMEBREW_HTTPS_PROXY="${proxyURL}"
  '';
}
