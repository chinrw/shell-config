{
  inputs,
  username,
  hostname,
  ...
}:
{
  imports = [
    ./configuration.nix
    ./homebrew.nix
    ./system-packages.nix

    inputs.home-manager.darwinModules.home-manager
    inputs.sops-nix.darwinModules.sops
    {
      home-manager = {
        # home.nix manages its own nixpkgs overlays/config, so we let the
        # home-manager-owned pkgs win rather than the system pkgs.
        useGlobalPkgs = false;
        useUserPackages = true;
        backupFileExtension = "hm-backup";
        extraSpecialArgs = {
          inherit inputs hostname username;
          inherit (inputs.self) outputs;
          stateVersion = "25.05";
          noGUI = false;
          isWsl = false;
          isWork = false;
          isServer = false;
          smallNode = false;
          platform = "aarch64-darwin";
        };
        users.${username} = ../home-manager/home.nix;
      };
    }
  ];
}
