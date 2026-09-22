# Automatic task titles

New Codex desktop and CLI tasks are named `project | summary` after their first
answer. The current model writes a short Chinese summary. The project is the
main Git worktree's directory name, or the current directory name outside Git.

Apply this Home Manager module, then review and trust its `SessionStart` and
`Stop` hooks in Codex (`/hooks` in the CLI). Start a new task to use
the rule. Existing tasks are left unchanged.

The model chooses the rename path by available tools. On desktop it uses
`set_thread_title`. When that tool is absent, it runs this hook's `--rename`
command with the session ID and summary. The helper starts a short-lived
`codex app-server --stdio`, calls `thread/name/set`, and reads the title back.
It does not start a model or a new task. The CLI's normal permission flow
applies to this command because it writes Codex session metadata outside the
workspace. A CLI view that caches the old title may need to be reopened.

`SessionStart` records new tasks under `$CODEX_HOME/rename-first-turn/`.
The first `Stop` requests one extra model continuation to set the title.
A persistent claim prevents repeated continuations and preserves subsequent
manual title edits, including after resuming the task. If either rename path
fails, naming is skipped without automatic retries or switching rename paths.

The hook definitions live in `~/.codex/hooks.json`. After changing the hook,
apply Home Manager and review any new trust request. Codex's `config.toml`
and session database remain managed by Codex.

The event contract is documented in the [official Hooks guide](https://learn.chatgpt.com/docs/hooks).
