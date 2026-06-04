---
description: "Ship a branch end-to-end — run the full test suite, open a PR, run /code-review max --fix, then rebase onto base and merge when everything is green"
argument-hint: "[base-branch] [--no-merge] [--draft] [--rebase|--squash]"
---

# Ship

Take the current feature branch all the way to a merged PR:

1. Run the project's **full test suite** (auto-detected).
2. Open a **pull request** (reuse `/pr`).
3. Run **`/code-review max --fix`** and resolve every finding.
4. **Rebase onto base and merge** the PR (a merge commit, every commit preserved)
   once every gate is green.

**Posture:** auto-detect, auto-fix, and auto-retry within bounds — but **STOP and
present options (use the `AskUserQuestion` tool) whenever the situation is
uncertain or the next action is hard to reverse and you are not confident it is
safe.** Never advance past a red gate. Report honestly at the end.

**Commits:** every commit this command makes (WIP in Phase 0, review fixes in
Phase 3) follows the repository's existing commit conventions — match the
surrounding message style and include any required trailers such as
`Signed-off-by`.

**Input** — parse `$ARGUMENTS`:
- First non-flag token → **base branch** (default: the repo's default branch).
- `--no-merge` → do everything up to and including review, but stop before merging.
- `--draft` → pass through to PR creation.
- Merge method — default **merge** (rebases onto base first, then adds a merge
  commit, preserving every commit); `--rebase` for a linear no-merge-commit
  result, `--squash` to collapse into one commit. Override only.

---

## Phase 0 — Preflight (fail fast, before running anything expensive)

```bash
git fetch origin --quiet            # refresh remote refs so base comparisons are accurate
git rev-parse --show-toplevel
git branch --show-current
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null \
  || git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
git status --short
```

| Check | Condition | Action if failed |
|---|---|---|
| On a feature branch | current branch ≠ `$DEFAULT` and not detached | **STOP**: "You're on the default branch (`<branch>`). Create/switch to a feature branch first, then re-run `/ship`." |
| `gh` available + authed | `gh auth status` succeeds | **STOP**: install (<https://cli.github.com/>) / `gh auth login`. |
| Has an `origin` remote | `git remote get-url origin` succeeds | **STOP**: no remote to push to. |
| Commits ahead of base | `git log origin/<base>..HEAD --oneline` not empty | **STOP**: "Nothing to ship — no commits ahead of `<base>`." |

**Uncommitted changes** (`git status --short` non-empty) → this is a judgment call:
present options with `AskUserQuestion` — *commit them now* (concise message
following the repo's commit style) / *abort so I can handle them manually*.

Detect an existing PR for this branch so we don't double-create:
```bash
gh pr list --head "$(git branch --show-current)" --state open --json number,url
```

---

## Phase 1 — Full test suite (auto-detected)

Detect the runner from repo markers (first match wins):

| Marker | Test command |
|---|---|
| `flake.nix` | `nix flake check` |
| `package.json` with a `test` script | `pnpm test` / `yarn test` / `npm test` — pick by lockfile |
| `Cargo.toml` | `cargo test` |
| `pyproject.toml` / `pytest.ini` / `tox.ini` | `pytest` (prefer `uv run pytest` / `poetry run pytest` if configured) |
| `go.mod` | `go test ./...` |
| `justfile` / `Makefile` with a `test` or `check` target | `just test` / `make test` (or `check`) |
| none of the above | **ASK** the user for the test command (`AskUserQuestion`) |

Remember the resolved command as `$TEST` — it's reused in Phase 3.

Run `$TEST`.
- **Pass** → continue to Phase 2.
- **Fail** → **auto-fix and retry**, bounded to **3 attempts**. Diagnose the
  failure and apply a minimal fix (use `/build-fix` or the language build
  resolver where it fits), then re-run `$TEST`. If still failing after the
  budget, or the needed fix is risky/ambiguous → **STOP** and present options
  (*keep auto-fixing* / *show me the failure and let me decide* / *abort*).

**Gate:** do not open a PR until `$TEST` is green.

---

## Phase 2 — Open the PR

- If Phase 0 found an **existing open PR** → reuse it; skip creation. Capture its number/URL.
- Otherwise **invoke `/pr <base>`** (add `--draft` if it was parsed). `/pr` pushes
  the branch, discovers the template, and runs `gh pr create`. Capture the PR
  number and URL from its output.

---

## Phase 3 — Code review with auto-fix ("fix all the findings")

1. **Invoke `/code-review max --fix`** — it reviews the branch diff and applies
   fixes to the working tree.
2. If it changed files → commit (`Apply /code-review max findings`) and
   `git push` to the PR branch.
3. **Re-run `$TEST`** — review fixes can break things. On failure, use the same
   auto-fix/retry/options flow as Phase 1.
4. **Address remaining findings.** `--fix` only applies mechanical changes;
   resolve the rest yourself where you're confident, commit, and push. For any
   finding that's ambiguous or that you can't safely auto-resolve, **present it
   with options** (*fix it this way* / *accept and proceed* / *abort*).
5. Re-run `/code-review max --fix` **once more** if substantial changes were
   applied, to confirm it comes back clean. Cap at **2 review passes** total —
   don't loop indefinitely.

---

## Phase 4 — Rebase onto base, then merge

- If `--no-merge` → **stop here**: report the PR is tested and review-clean, left open.
- **Rebase the branch onto the latest base first** — keeps history linear and
  surfaces any conflicts locally rather than on GitHub:
  ```bash
  git fetch origin
  git rebase origin/<base>
  ```
  - Conflicts → **STOP** and present options (*I'll resolve them now* / *abort*).
  - After a clean rebase, update the PR branch: `git push --force-with-lease`
    (never plain `--force`).
- Verify mergeability and CI:
  ```bash
  gh pr view <n> --json mergeable,mergeStateStatus,reviewDecision
  gh pr checks <n> --watch 2>/dev/null || true   # only if the repo has checks
  ```
  Red checks → auto-fix/retry (Phase 1 flow) or present options. No checks
  configured → proceed. Still not mergeable → **STOP** with options.
- **Merge** — default **merge commit** (the branch was already rebased onto
  `<base>` above, so this is a clean merge commit over linear history, with every
  commit preserved). Honor an override flag if one was passed:
  ```bash
  gh pr merge <n> --merge --delete-branch      # default (merge commit)
  # --rebase → gh pr merge <n> --rebase --delete-branch   (linear, no merge commit)
  # --squash → gh pr merge <n> --squash --delete-branch   (collapse to one commit)
  ```
- Post-merge: return to base and fast-forward:
  ```bash
  git checkout <base> && git pull --ff-only
  ```

---

## Phase 5 — Report

Summarize plainly:

```
Shipped PR #<n>: <title>
  URL:          <url>
  Test suite:   $TEST  → green (<attempts> attempt(s))
  Review:       /code-review max --fix → <findings applied>, <N> deferred to you
  Merge:        merge commit → <merge-sha> onto <base>, branch deleted
  Back on:      <base> (fast-forwarded)
```

If anything was deferred, left open (`--no-merge`), or stopped early, say so
clearly with the exact reason and the command to resume.

---

## STOP and present options (`AskUserQuestion`) when:

- On the default branch or detached HEAD (hard stop with guidance).
- Uncommitted changes are present at start.
- A test failure can't be confidently auto-fixed within the retry budget.
- `/code-review` surfaces findings that aren't safe to auto-resolve.
- The PR isn't mergeable, has conflicts, or CI is red and can't be auto-fixed.
- Before any force action — only ever `git push --force-with-lease`, never `--force`.
