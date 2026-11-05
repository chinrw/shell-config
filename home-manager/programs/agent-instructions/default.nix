# Instruction text shared by every coding agent.
#
# Keep the parts tool-agnostic. Anything naming a tool that only one agent
# has belongs in that agent's own instruction file instead.
#
# Exposes both forms on purpose: `text` so a caller can splice it into a larger
# document without triggering IFD, `file` for callers that just need a path.
{ lib, pkgs }:
let
  text = lib.concatMapStringsSep "\n" builtins.readFile [
    ./writing-style.md
    ./git-commits.md
    ./decision-making.md
    ./upstream-repos.md
  ];
in
{
  inherit text;
  file = pkgs.writeText "agent-instructions.md" text;
}
