# Instruction text shared by every coding agent.
#
# Keep shared behavior independent of the agent. Name a tool only as an
# example of how that agent follows the shared rule.
{ lib, pkgs }:
let
  text = lib.concatMapStringsSep "\n" builtins.readFile [
    ./writing-style.md
    ./git-commits.md
    ./decision-making.md
    ./upstream-repos.md
  ];
  file = pkgs.writeText "agent-instructions.md" text;
in
{
  inherit text file;

  assemble =
    {
      tool,
      directory,
      filename,
      localFilename,
      hostname,
      baseText,
      sharedFile,
      extraText ? "",
    }:
    let
      baseFile = pkgs.writeText "${tool}-instructions-base" baseText;
      extraFile = pkgs.writeText "${tool}-instructions-extra" extraText;
      assembler = pkgs.writeShellApplication {
        name = "assemble-agent-instructions";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          target_dir=${lib.escapeShellArg directory}
          local_md="$target_dir/${localFilename}"
          final_md="$target_dir/${filename}"

          mkdir -p "$target_dir"
          if [ ! -e "$local_md" ] && [ ! -L "$local_md" ]; then
            cat > "$local_md" <<'EOF'
          <!--
          This file holds host-local ${tool} instructions and is not tracked by Nix.
          Edit it here; Home Manager appends it to ${directory}/${filename}
          on the next activation.
          -->
          EOF
          fi

          tmp_md="$(mktemp "$target_dir/.agent-instructions.XXXXXX")"
          trap 'rm -f "$tmp_md"' EXIT
          {
            cat ${baseFile} ${lib.escapeShellArg (toString sharedFile)}
            ${lib.optionalString (extraText != "") "cat ${extraFile}"}
            if [ -s "$local_md" ]; then
              printf '\n\n## Local additions for %s (%s)\n\n' ${lib.escapeShellArg tool} ${lib.escapeShellArg hostname}
              cat "$local_md"
            fi
          } > "$tmp_md"
          mv -T "$tmp_md" "$final_md"
        '';
      };
    in
    ''
      run ${assembler}/bin/assemble-agent-instructions
    '';
}
