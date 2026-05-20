# macOS-only home-manager modules.
#
# Imported as a unit from home.nix, gated on `hostname == "macos"`.
# Add future macOS-specific home-manager modules to the list below.
{
  imports = [
    ./xray.nix
  ];
}
