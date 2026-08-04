# Instruction text shared by every coding agent: Claude (~/.claude/CLAUDE.md),
# Codex (~/.codex/AGENTS.md) and opencode (`instructions` in opencode.jsonc).
#
# Keep the parts tool-agnostic. Anything naming a Claude-only tool or an
# opencode-only agent belongs in that tool's own instruction file instead.
#
# Exposes both forms on purpose: `text` so a caller can splice it into a larger
# document without triggering IFD, `file` for callers that just need a path.
{ lib, pkgs }:
let
  text = lib.concatMapStringsSep "\n" builtins.readFile [
    ./writing-style.md
    ./git-commits.md
    ./decision-making.md
  ];
in
{
  inherit text;
  file = pkgs.writeText "agent-instructions.md" text;
}
