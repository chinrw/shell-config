# Local binary cache registry, keyed by a short name.
#
# A host opts into a cache by adding its name to `localCaches` in that host's
# `helpers.mkHome { ... }` call in flake.nix, e.g.:
#
#   "chin39@proxmox" = helpers.mkHome {
#     hostname = "proxmox";
#     localCaches = [ "home" ];
#   };
#
# Opt-in is by cache name on the flake.nix entry (not by hostname), so hosts
# that share a hostname (e.g. chin39@work vs chin39@vm-work, both "work") stay
# independently selectable.
#
# Adding another local network = add an entry here, then list its name on the
# hosts that can reach it. Each cache's URL + signing key are defined once here.
#
# The public key must also be trusted by the nix daemon on each consuming host:
#   - NixOS hosts: `chin39` is a trusted-user, so the home-manager-written
#     ~/.config/nix/nix.conf is honored automatically.
#   - non-NixOS hosts: add `chin39` to `trusted-users` in /etc/nix/nix.conf once,
#     otherwise the daemon ignores the substituter and falls back to public caches.
{
  # home LAN (192.168.0.0/24) — served by vm-nix's nix-serve
  home = {
    url = "http://192.168.0.240:5000";
    publicKey = "vm-nix:5SZMXyCcqGm5z/GJNdx+wRyyE8CKtcvSsaDY0uFp25s=";
  };

  # Example — a second network with its own nix-serve and host set.
  # Uncomment, fill in the real key, then add `"office"` to `localCaches` on the
  # hosts that live on that network.
  #
  # office = {
  #   url = "http://10.0.5.10:5000";
  #   publicKey = "office-nix:REPLACE_WITH_REAL_PUBLIC_KEY=";
  # };
}
