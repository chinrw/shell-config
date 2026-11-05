# Shared agent instructions

Home Manager publishes the rules in this directory at `~/.agents/AGENTS.md`,
together with local additions from `~/.agents/AGENTS.local.md`.
Edit the Markdown sources here to change the rules for Codex, Claude and Pi:

- `writing-style.md` defines how to write comments, documentation and tracker text.
- `git-commits.md` defines commit messages and Git identity requirements.
- `decision-making.md` defines implementation scope and when to ask the user.
- `upstream-repos.md` defines authorization for issues, pull requests and pushes.

Use `~/.agents/AGENTS.local.md` for instructions that every agent should follow
on this host. On activation, Home Manager first generates the shared file,
then combines it with each tool's specific instructions and local additions.
The tools load their own entry files; they do not need to discover
`~/.agents/AGENTS.md` themselves.

| Tool | Entry file | Local additions |
| --- | --- | --- |
| Codex | `~/.codex/AGENTS.md` | `~/.codex/AGENTS.local.md` |
| Claude | `~/.claude/CLAUDE.md` | `~/.claude/CLAUDE.local.md` |
| Pi | `~/.pi/agent/AGENTS.md` | `~/.pi/agent/AGENTS.local.md` |

Edit a local additions file for rules that apply only to that tool on that
host. Home Manager creates missing local files and preserves existing ones.
The next activation includes those edits in the tool's entry file.

Local additions and the generated files that include them stay in the home
directory and are not copied into the Nix store. Generated files are replaced
on activation, so edit their sources or local additions instead.
