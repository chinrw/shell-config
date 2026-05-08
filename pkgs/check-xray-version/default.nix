{
  writeShellApplication,
  curl,
  jq,
  gnused,
  gawk,
  git,
  coreutils,
}:
writeShellApplication {
  name = "check-xray-version";
  runtimeInputs = [
    curl
    jq
    gnused
    gawk
    git
    coreutils
  ];
  text = ''
    set -euo pipefail

    flake_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
    overlay_file="$flake_root/overlays/default.nix"

    if [ ! -f "$overlay_file" ]; then
      echo "ERROR: $overlay_file not found. Run from inside the shell-config flake." >&2
      exit 2
    fi

    pinned=$(awk '
      /# xray-pin-fields-begin/ { in_block = 1; next }
      /# xray-pin-fields-end/   { in_block = 0; next }
      in_block && /version *=/  { match($0, /"[^"]*"/); print substr($0, RSTART+1, RLENGTH-2); exit }
    ' "$overlay_file")

    if [ -z "$pinned" ]; then
      echo "ERROR: could not parse pinned version from $overlay_file" >&2
      echo "       expected the xray override to live between '# xray-pin-fields-begin' and '# xray-pin-fields-end'" >&2
      exit 3
    fi

    latest=$(curl -fsS https://api.github.com/repos/XTLS/Xray-core/releases/latest \
      | jq -r .tag_name | sed 's/^v//')

    printf 'Pinned:  v%s\n' "$pinned"
    printf 'Latest:  v%s\n' "$latest"

    if [ "$pinned" = "$latest" ]; then
      echo 'OK: pinned matches latest stable.'
      exit 0
    fi

    higher=$(printf '%s\n%s\n' "$pinned" "$latest" | sort -V | tail -1)
    if [ "$higher" = "$latest" ]; then
      printf 'WARN: upstream stable v%s is higher than pinned v%s\n' "$latest" "$pinned"
      printf '      bump overlays/default.nix manually (between the xray-pin-fields markers)\n'
      printf '      and refresh hashes via two iterative nix build runs\n'
      exit 1
    fi
    printf 'INFO: pinned (v%s) is higher than latest stable (v%s) -- probably tracking pre-release\n' "$pinned" "$latest"
    exit 0
  '';
}
