# Automatic task titles

This module names eligible new Codex tasks as `project | summary` after a
completed answer. The project is the main Git worktree's directory name, or
the current directory name outside Git. An independent GPT-6 Luna call
generates the Chinese summary at high reasoning effort.
Titles describe the overall requested task, retain business names and version
identifiers, and use the answer only to resolve ambiguity.

Use the module's Codex package with a login that supports Luna. The module
installs its hook definitions in `~/.codex/hooks.json`. A different
`CODEX_HOME` needs the corresponding hook configuration.

Apply this Home Manager module, then review and trust its `SessionStart`,
`UserPromptSubmit`, and `Stop` hooks in Codex (`/hooks` in the CLI). Start a new
task to use the rule. Existing tasks are left unchanged, including tasks
registered by the earlier version of this hook.

Each eligible task starts at most one extra summary attempt. The summary
call reuses the existing Codex login and runs in a temporary directory. It
receives at most 4,000 characters each from the first captured user request
and the completed answer delivered to the claiming Stop hook. It skips user
configuration and project instructions, disables hooks to prevent recursion,
and uses an ephemeral session. This does not isolate every inherited
environment setting or disable every built-in tool.

`Stop` runs in the background and updates the title through the app-server
metadata API. It returns an empty result, so neither the naming prompt nor
Luna's response enters the main conversation. Codex may still display hook
execution status. A client that caches the old title may need to be reopened.

Generation gets up to 45 seconds within a shared workflow budget. Missing
text or failed generation does not update the title. Once claimed, an attempt
is not retried automatically. A metadata error after writing the title may
mean the update succeeded even though verification failed.

Manual-title protection is best-effort. A change detected between the two
metadata reads prevents the update, and later turns do not rename a claimed
task again. The write is not atomic with manual edits: a manual name set
before the first read or between the final read and write can be replaced.

For diagnostics, inspect `$CODEX_HOME/rename-first-turn/`, or
`~/.codex/rename-first-turn/` when `CODEX_HOME` is unset. Records can be
`pending`, `running`, `renamed`, `skipped`, or `failed`. Abrupt termination can
leave a `running` record after its process exits. Do not reset it to retry an
old task. The captured request is removed when Stop claims the attempt;
pending records retain it. Resuming a pending task does not reset its first
request, but a later completed answer can still trigger its naming attempt.

The hook definitions live in `~/.codex/hooks.json`. After changing the hook,
apply Home Manager and review any new trust request. Codex's `config.toml`
and session database remain managed by Codex.

The event contract is documented in the [official Hooks guide](https://learn.chatgpt.com/docs/hooks).
