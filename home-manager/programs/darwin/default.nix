# macOS-only home-manager modules.
#
# Imported as a unit from home.nix, gated on `hostname == "macos"`.
# Add future macOS-specific home-manager modules to the list below.
let
  noProxy = (import ../../../lib/proxy.nix).noProxy;
in
{
  imports = [ ];
  home.sessionVariables = {
    no_proxy = noProxy;
    NO_PROXY = noProxy;
  };
}
