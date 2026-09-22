# Automatic task titles

New Codex desktop tasks are named `project | summary` after their first answer.
The current model writes a short Chinese summary and uses the desktop title
tool. The project is the main Git worktree's directory name, or the current
directory name outside Git.

Apply this Home Manager module, then review and trust its `SessionStart` and
`Stop` hooks in Codex (`/hooks` in the CLI). Start a new desktop task to use
the rule. Existing tasks are left unchanged.

`SessionStart` records new tasks under `$CODEX_HOME/rename-first-turn/`.
The first `Stop` requests one extra model continuation to set the title.
A persistent claim prevents repeated continuations and preserves subsequent
manual title edits, including after resuming the task. If the title tool is
unavailable or fails, naming is skipped without automatic retries. This rule
requires the desktop title tool and does not provide CLI-only renaming.

The hook definitions live in `~/.codex/hooks.json`. After changing the hook,
apply Home Manager and review any new trust request. Codex's `config.toml`
and session database remain managed by Codex.

The event contract is documented in the [official Hooks guide](https://learn.chatgpt.com/docs/hooks).
