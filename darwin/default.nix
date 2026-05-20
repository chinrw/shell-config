{
  inputs,
  ...
}:
{
  # home-manager is intentionally NOT wired in here: home.nix is managed
  # standalone via homeConfigurations."chin39@macos" (`home-manager switch`).
  # Importing the home-manager darwin module too would double-manage the
  # same dotfiles and launchd agents. nix-darwin owns system config only.
  imports = [
    ./configuration.nix
    ./homebrew.nix
    ./system-packages.nix

    inputs.sops-nix.darwinModules.sops
  ];
}
