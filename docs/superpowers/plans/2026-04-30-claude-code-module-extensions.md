# claude-code Module Extensions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing `home-manager/programs/claude-code/` module with four capabilities: pinned-flake-input source for `everything-claude-code`, switch-time `~/.claude/CLAUDE.md` rebuild that appends a host-local `CLAUDE.local.md`, declarative `mcpServers` option, and `extraHooks` option with per-event concat semantics.

**Architecture:** All changes land in three Nix files (`flake.nix`, `home-manager/home.nix`, `home-manager/programs/claude-code/default.nix`). No new files except the local seed that the activation script writes on first run. The activation block grows three new responsibilities (CLAUDE.md rebuild + local seed, MCP merge into `~/.claude.json`, optional extra-hook merge into the settings JSON).

**Tech Stack:** Nix flakes, home-manager 24.11+, bash 5.x, `jq`, `findutils`, `git`. No additional language runtimes introduced.

**Spec reference:** `docs/superpowers/specs/2026-04-30-claude-code-config-nix-design.md`

**Repo paths used in this plan:**
- Repo root: `/home/chin39/shell-config`
- Active host config: `homeConfigurations."chin39@vm-nix"`
- Apply command: `home-manager switch --flake .#chin39@vm-nix`
- Build-only command (eval check): `home-manager build --flake .#chin39@vm-nix`
- Sandbox note: `home-manager build/switch` and `nix flake update` need filesystem access outside the default sandbox; run them with `dangerouslyDisableSandbox: true` if the executor environment uses Claude Code's sandbox.

**Commit message convention** (from user-scope CLAUDE.md):
- Format: `<type>: <subject>` then a bullet body, then `Signed-off-by: Ruowen Qin <chinqrw@gmail.com>` as the last line. Types: `feat`, `fix`, `refactor`, `docs`, `chore`. **No** `Co-Authored-By:` lines. **No** auto-push.

---

## File Structure

| File | Change | Responsibility after this lands |
|---|---|---|
| `flake.nix` | Add `inputs.everything-claude-code` | Single declarative source pointer with commit pinned in `flake.lock` |
| `home-manager/home.nix:78-84` | Add `source = inputs.everything-claude-code;` to the existing claude-code import | Pass the flake input through to the module |
| `home-manager/programs/claude-code/default.nix` | Significant edits in the `let`, options, and activation blocks | Compose `~/.claude/{settings.json,CLAUDE.md,hooks/}` and the symlink farms; manage MCP merge and hook extension |
| `home-manager/programs/claude-code/CLAUDE.md` | Untouched | Still the user-scope base instructions |
| `home-manager/programs/claude-code/hooks/*.sh` | Untouched | Still the two committed hook scripts |

No new module files. `~/.claude/CLAUDE.local.md` is created on the user's machine by the activation script — it is NOT in the repo.

---

## Pre-flight

- [ ] **Step P1: Confirm working directory and clean baseline**

```bash
cd /home/chin39/shell-config
git status --short
```

Expected: at most untracked dotfiles (`.bashrc`, `.zshrc`, etc.) — those are noise. Tracked files in `home-manager/`, `flake.nix`, `docs/superpowers/` should be clean. If anything else is staged or modified, stop and ask the user before continuing — don't merge unrelated work into these commits.

- [ ] **Step P2: Sanity-check the live module before any changes**

Run a build to confirm the existing module evaluates cleanly so any future failure is attributable to this plan:

```bash
home-manager build --flake .#chin39@vm-nix
```

Expected: completes and produces `./result`. If it fails, stop and fix the pre-existing breakage before continuing.

---

## Task 1: Add `everything-claude-code` as a pinned flake input

**Files:**
- Modify: `flake.nix` (inputs block, around the existing `nix-index-database` entry)

- [ ] **Step 1: Add the input**

Open `flake.nix` and locate the `inputs = { ... };` block (around line 26-95 of the current file). Add this entry alongside the other `inputs.*` declarations (placement is cosmetic — group it with the other content sources like `neovim-nightly-overlay`):

```nix
    everything-claude-code = {
      url = "github:affaan-m/everything-claude-code";
      flake = false;
    };
```

`flake = false` tells Nix this URL is a plain source tree, not a flake. The store path you get from `inputs.everything-claude-code` is the unpacked repo root.

- [ ] **Step 2: Stage the change so flakes can see it, then update the lock**

Nix flakes only see files tracked by git. Stage the edit before evaluating:

```bash
git -C /home/chin39/shell-config add flake.nix
```

Then lock it:

```bash
nix flake lock --update-input everything-claude-code
```

Expected: command succeeds and `flake.lock` is modified. `git diff flake.lock` should show a new node and an entry under `nodes.root.inputs.everything-claude-code`.

If the executor environment uses Claude Code's sandbox and the command fails with a sandbox-related error (SQLite/network/path), retry with `dangerouslyDisableSandbox: true`.

- [ ] **Step 3: Verify the input resolves**

```bash
nix eval --raw .#nixosConfigurations.vm-nix.config.system.build.toplevel.outPath 2>/dev/null >/dev/null || true
nix eval --raw .#homeConfigurations."chin39@vm-nix".activationPackage.outPath 2>/dev/null | head -c 80
echo
```

The second eval prints a `/nix/store/...` path if the home configuration still evaluates — meaning the new input doesn't break anything yet (we haven't wired it).

A more direct check that the input's content is reachable:

```bash
nix eval --raw '.#inputs' 2>&1 | head -1
```

(The exact `nix eval` form for inputs varies; you can also confirm via `nix flake metadata . | grep -A1 everything-claude-code`.)

```bash
nix flake metadata --json . 2>/dev/null | jq -r '.locks.nodes."everything-claude-code".locked.rev'
```

Expected: a 40-char SHA. If it prints empty or errors, the input wasn't locked — re-run Step 2.

- [ ] **Step 4: Commit**

```bash
git -C /home/chin39/shell-config add flake.nix flake.lock
git -C /home/chin39/shell-config commit -m "$(cat <<'EOF'
feat: pin everything-claude-code as flake input

- replaces the imperative `git clone` of affaan-m/everything-claude-code
- locks the upstream commit in flake.lock for cross-host reproducibility
- consumed by home-manager/programs/claude-code/ in a follow-up commit

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>
EOF
)"
```

Expected: commit succeeds; `git log -1 --stat` shows two files changed.

---

## Task 2: Wire the `source` arg through and migrate the symlink farm

This task removes the `git clone` activation step, repoints the symlink farm at the flake-input store path, and broadens the stale-symlink sweep so the legacy `~/Documents/play/everything-claude-code/*` links are cleaned on first switch. The DAG gate stays `writeBoundary` for now; Task 3 changes it.

**Files:**
- Modify: `home-manager/home.nix:78-84`
- Modify: `home-manager/programs/claude-code/default.nix`

- [ ] **Step 1: Pass `source` through `home.nix`**

Open `home-manager/home.nix`. Find the existing claude-code import (currently lines 78-84):

```nix
  ++ lib.optionals (!smallNode) [
    (import ./programs/claude-code {
      inherit lib pkgs config hostname;
      # Per-host CLAUDE.md additions; default empty. Override per host as needed.
      extraInstructions = "";
    })
  ]
```

Replace it with:

```nix
  ++ lib.optionals (!smallNode) [
    (import ./programs/claude-code {
      inherit lib pkgs config hostname;
      source = inputs.everything-claude-code;
      # Per-host CLAUDE.md additions; default empty. Override per host as needed.
      extraInstructions = "";
    })
  ]
```

`inputs` is already in the function args at the top of `home.nix:4`, so it's in scope. No other change to `home.nix`.

- [ ] **Step 2: Add `source` to the module signature**

Open `home-manager/programs/claude-code/default.nix`. Replace the current arg block:

```nix
{
  config,
  lib,
  pkgs,
  hostname,
  extraInstructions ? "",
  ...
}:
```

with:

```nix
{
  config,
  lib,
  pkgs,
  hostname,
  source,
  extraInstructions ? "",
  ...
}:
```

`source` has no default — it's required. Hosts that don't enable this module won't import it (the call site in `home.nix` is gated by `lib.optionals (!smallNode)`), so the lack of default is intentional.

- [ ] **Step 3: Repoint and broaden the symlink farm**

In the same file, locate the `home.activation.claudeCodeAssets` block. Replace its body with this version (changes: `REPO` now uses `${source}`; the `git clone` is gone; the sweep matches both old and new source paths; the `link_children` function and the four invocations are otherwise unchanged):

```nix
  home.activation.claudeCodeAssets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    REPO="${source}"
    CLAUDE="${config.home.homeDirectory}/.claude"

    link_children() {
      local src="$1"
      local dst="$2"
      [ -d "$src" ] || return 0
      run mkdir -p "$dst"
      if [ -L "$dst" ]; then
        run rm "$dst"
        run mkdir -p "$dst"
      fi
      # Sweep stale symlinks pointing at either the current $REPO or the legacy
      # ~/Documents/play/everything-claude-code/* location whose target no longer exists.
      run ${pkgs.findutils}/bin/find "$dst" -maxdepth 1 -type l \
        \( -lname "$REPO/*" -o -lname "*/everything-claude-code/*" \) \
        -exec sh -c '[ ! -e "$1" ] && rm "$1"' _ {} \;
      for entry in "$src"/*; do
        [ -e "$entry" ] || continue
        local name target
        name=$(basename "$entry")
        target="$dst/$name"
        # Don't clobber a non-symlink file at this path.
        if [ -e "$target" ] && [ ! -L "$target" ]; then
          continue
        fi
        run ln -sfn "$entry" "$target"
      done
    }

    link_children "$REPO/agents"   "$CLAUDE/agents"
    link_children "$REPO/commands" "$CLAUDE/commands"
    link_children "$REPO/skills"   "$CLAUDE/skills"
    link_children "$REPO/rules"    "$CLAUDE/rules"
  '';
```

Note: the previous `if [ ! -d "$REPO" ]; then run git clone ... fi` block is **removed**. The flake input is the source of truth now. `~/Documents/play/everything-claude-code/` is left in place if the user has it (for hand-editing); the activation script does not delete it.

- [ ] **Step 4: Stage and build**

```bash
git -C /home/chin39/shell-config add home-manager/home.nix home-manager/programs/claude-code/default.nix
home-manager build --flake .#chin39@vm-nix
```

Expected: builds successfully and produces `./result`. If you get an error like `error: undefined variable 'source'`, you missed Step 2.

If the eval errors complain about `inputs` not being in scope inside the module, the call-site change in Step 1 is wrong — `source` should come from the call site, not be looked up inside the module.

- [ ] **Step 5: Inspect the generated activation script**

Confirm the `git clone` line is gone and the `REPO=` line points at the Nix store:

```bash
grep -A4 'Activating .*claudeCodeAssets' /home/chin39/shell-config/result/activate | head -10
```

Expected output starts with:
```
_iNote "Activating %s" "claudeCodeAssets"
REPO="/nix/store/...-source"
CLAUDE="/home/chin39/.claude"
```

No occurrence of `git clone` should appear. Verify with:

```bash
grep -c 'git clone' /home/chin39/shell-config/result/activate
```

Expected: `0`.

- [ ] **Step 6: Apply and verify the symlink farm migrated**

```bash
home-manager switch --flake .#chin39@vm-nix
```

Then verify a few symlinks in each managed dir now point into the Nix store, and no broken legacy links remain:

```bash
readlink ~/.claude/agents/code-reviewer.md
readlink ~/.claude/skills/tdd-workflow
readlink ~/.claude/commands/code-review.md
readlink ~/.claude/rules/common
```

Expected: each path starts with `/nix/store/` (specifically the `everything-claude-code` source store path).

```bash
find ~/.claude/agents ~/.claude/commands ~/.claude/skills ~/.claude/rules \
  -maxdepth 1 -type l ! -exec test -e {} \; -print
```

Expected: empty output — no broken symlinks.

- [ ] **Step 7: Commit**

```bash
git -C /home/chin39/shell-config commit -m "$(cat <<'EOF'
refactor(claude-code): vendor everything-claude-code via flake input

- consume the new `everything-claude-code` flake input instead of cloning at activation
- broaden the stale-symlink sweep to also match legacy ~/Documents/play/* targets
- drop the `git clone` step from the activation script entirely
- ~/Documents/play/everything-claude-code/ is no longer load-bearing; users may keep or remove

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>
EOF
)"
```

---

## Task 3: CLAUDE.md activation rebuild + CLAUDE.local.md seed

This task drops the `home.file` for CLAUDE.md, adds a regenerate-on-switch step that concatenates the Nix-managed base with `~/.claude/CLAUDE.local.md` (seeded on first run), and moves the activation DAG gate so the rebuild happens AFTER home-manager finishes orphan cleanup of the prior generation's symlink at that path.

**Files:**
- Modify: `home-manager/programs/claude-code/default.nix`

- [ ] **Step 1: Remove the `home.file` entry for CLAUDE.md**

Locate the block:

```nix
  home.file.".claude/CLAUDE.md" = {
    text = fullClaudeMd;
    force = true;
  };
```

Delete it. The `let` binding for `fullClaudeMd` will be reused in Step 2 — leave the `let` content alone for now.

- [ ] **Step 2: Materialize the base content as a Nix-store file**

In the existing `let` block, rename `fullClaudeMd` to make its role clearer and wrap it in `pkgs.writeText`. Replace:

```nix
  baseClaudeMd = builtins.readFile ./CLAUDE.md;
  fullClaudeMd =
    if extraInstructions == "" then
      baseClaudeMd
    else
      baseClaudeMd + "\n\n## Host-specific (${hostname})\n\n" + extraInstructions;
```

with:

```nix
  baseClaudeMd = builtins.readFile ./CLAUDE.md;
  withHostExtra =
    if extraInstructions == "" then
      baseClaudeMd
    else
      baseClaudeMd + "\n\n## Host-specific (${hostname})\n\n" + extraInstructions;
  baseClaudeMdFile = pkgs.writeText "claude-md-base" withHostExtra;
```

`baseClaudeMdFile` is a Nix-store path the activation script will `cat`.

- [ ] **Step 3: Move the activation DAG gate to `linkGeneration`**

In `home.activation.claudeCodeAssets`, change:

```nix
  home.activation.claudeCodeAssets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
```

to:

```nix
  home.activation.claudeCodeAssets = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
```

Why: `linkGeneration` removes orphan symlinks from the previous generation. The previous generation managed `~/.claude/CLAUDE.md` via `home.file`; after this commit it doesn't, so home-manager will treat it as an orphan and remove the symlink — but only after `writeBoundary`. Running our rebuild AFTER `linkGeneration` guarantees the orphan is gone before we write the new file.

- [ ] **Step 4: Append the CLAUDE.md rebuild + local seed to the activation body**

Inside the activation script body, after the four `link_children` calls, add:

```bash
    CLAUDE_MD_BASE="${baseClaudeMdFile}"
    LOCAL_MD="$CLAUDE/CLAUDE.local.md"
    FINAL_MD="$CLAUDE/CLAUDE.md"

    # Seed CLAUDE.local.md on first run only — never touch existing user content.
    if [ ! -e "$LOCAL_MD" ]; then
      cat > "$LOCAL_MD" <<'EOF'
<!--
This file is local to this host and not tracked by Nix.
Edits land in ~/.claude/CLAUDE.md after the next `home-manager switch`,
appended below the Nix-managed base content.

Use it for host-specific shortcuts, side-project context, or anything you
want Claude to see at user scope but don't want to commit to the
shell-config flake.

Replace this comment with real content. Claude ignores HTML comments in
markdown, so the seed text is not visible in CLAUDE.md until you replace it.
-->
EOF
    fi

    # Strip a previous Nix symlink at ~/.claude/CLAUDE.md if present, then rebuild.
    if [ -L "$FINAL_MD" ]; then
      run rm "$FINAL_MD"
    fi

    TMP_MD="$(${pkgs.coreutils}/bin/mktemp)"
    {
      ${pkgs.coreutils}/bin/cat "$CLAUDE_MD_BASE"
      if [ -s "$LOCAL_MD" ]; then
        printf '\n\n## Local additions (%s)\n\n' "${hostname}"
        ${pkgs.coreutils}/bin/cat "$LOCAL_MD"
      fi
    } > "$TMP_MD"
    run mv "$TMP_MD" "$FINAL_MD"
```

Notes:
- The HTML-comment block in the heredoc means Claude (which renders markdown) ignores it. The deployed `CLAUDE.md` on a fresh host with the default seed has no visible local additions — exactly the same prompt content as a host with no `CLAUDE.local.md`.
- `mktemp` + `mv` is atomic on the same filesystem, so a Claude session reading mid-switch sees either the old file or the new one.
- The full paths to `coreutils` keep activation deterministic regardless of the user's `PATH`.

- [ ] **Step 5: Build and inspect**

```bash
home-manager build --flake .#chin39@vm-nix
```

Expected: builds successfully. Inspect the generated activation:

```bash
grep -A30 'CLAUDE_MD_BASE=' /home/chin39/shell-config/result/activate | head -40
```

Expected: shows the seed heredoc and the `mktemp + mv` block. The `CLAUDE_MD_BASE=` value should be a `/nix/store/...-claude-md-base` path.

Confirm `home.file` no longer manages CLAUDE.md:

```bash
ls /home/chin39/shell-config/result/home-files/.claude/ | grep -i claude.md
```

Expected: empty output. (`settings.json` and `hooks/` will still appear, but `CLAUDE.md` should not.)

- [ ] **Step 6: Apply and verify**

```bash
home-manager switch --flake .#chin39@vm-nix
```

Then:

```bash
ls -la ~/.claude/CLAUDE.md ~/.claude/CLAUDE.local.md
```

Expected:
- `~/.claude/CLAUDE.md` is `-rw-...` (regular file, not a symlink — no `l` in the mode string).
- `~/.claude/CLAUDE.local.md` is a regular file containing the seed heredoc.

```bash
head -5 ~/.claude/CLAUDE.local.md
```

Expected: starts with `<!--` and references "local to this host".

```bash
diff <(cat /home/chin39/shell-config/home-manager/programs/claude-code/CLAUDE.md) <(head -c "$(stat -c%s /home/chin39/shell-config/home-manager/programs/claude-code/CLAUDE.md)" ~/.claude/CLAUDE.md)
```

Expected: empty output (the first N bytes of `~/.claude/CLAUDE.md` match the source `CLAUDE.md` byte-for-byte).

- [ ] **Step 7: Test the local-edit propagation**

```bash
echo '## Sentinel' >> ~/.claude/CLAUDE.local.md
echo 'this should appear in CLAUDE.md after switch' >> ~/.claude/CLAUDE.local.md
home-manager switch --flake .#chin39@vm-nix
tail -5 ~/.claude/CLAUDE.md
```

Expected: the `tail` ends with the sentinel block under a `## Local additions (vm-nix)` heading. If the `## Sentinel` line is missing, the `[ -s "$LOCAL_MD" ]` branch isn't firing — re-check Step 4's heredoc.

Now revert the test edit:

```bash
${EDITOR:-nano} ~/.claude/CLAUDE.local.md   # remove the two sentinel lines
home-manager switch --flake .#chin39@vm-nix
```

- [ ] **Step 8: Commit**

```bash
git -C /home/chin39/shell-config add home-manager/programs/claude-code/default.nix
git -C /home/chin39/shell-config commit -m "$(cat <<'EOF'
feat(claude-code): rebuild CLAUDE.md from base + ~/.claude/CLAUDE.local.md at switch

- drops `home.file` management of ~/.claude/CLAUDE.md; the file is now a
  regular file written by the activation script
- seeds ~/.claude/CLAUDE.local.md with an HTML-commented note on first run
- moves the activation DAG gate to `linkGeneration` so the rebuild runs
  after home-manager removes the prior generation's symlink at that path
- atomic write via mktemp + mv

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>
EOF
)"
```

---

## Task 4: `mcpServers` declarative option

**Files:**
- Modify: `home-manager/programs/claude-code/default.nix`

- [ ] **Step 1: Add the `mcpServers` arg**

In the module signature, add `mcpServers ? { },` between `source,` and `extraInstructions ? "",`. The arg block becomes:

```nix
{
  config,
  lib,
  pkgs,
  hostname,
  source,
  mcpServers ? { },
  extraInstructions ? "",
  ...
}:
```

- [ ] **Step 2: Build the MCP server file and the optional activation snippet**

Inside the existing `let` block, after `baseClaudeMdFile = ...;`, add:

```nix
  mcpServersFile = pkgs.writeText "claude-mcp-servers.json"
    (builtins.toJSON mcpServers);

  mcpActivation = lib.optionalString (mcpServers != { }) ''
    CLAUDE_JSON="$HOME/.claude.json"
    TMP="$(${pkgs.coreutils}/bin/mktemp)"
    if [ -f "$CLAUDE_JSON" ]; then
      ${pkgs.jq}/bin/jq --slurpfile m ${mcpServersFile} \
        '.mcpServers = $m[0]' "$CLAUDE_JSON" > "$TMP"
    else
      ${pkgs.jq}/bin/jq -n --slurpfile m ${mcpServersFile} \
        '{ mcpServers: $m[0] }' > "$TMP"
    fi
    run mv "$TMP" "$CLAUDE_JSON"
  '';
```

`lib.optionalString (mcpServers != { })` returns `""` when no MCP servers are declared, so the entire block disappears at Nix evaluation time — no activation cost and `~/.claude.json` is never touched.

`--slurpfile` reads the MCP config from a Nix-store file path, so user-supplied JSON values containing literal apostrophes or backslashes can never break the shell quoting.

- [ ] **Step 3: Concatenate `mcpActivation` into the activation body**

In the `home.activation.claudeCodeAssets` declaration, the body is currently a single multi-line string. Change the assignment so `mcpActivation` is appended after the existing body:

```nix
  home.activation.claudeCodeAssets = lib.hm.dag.entryAfter [ "linkGeneration" ] (''
    REPO="${source}"
    CLAUDE="${config.home.homeDirectory}/.claude"

    link_children() {
      ...   # existing body unchanged
    }

    link_children "$REPO/agents"   "$CLAUDE/agents"
    link_children "$REPO/commands" "$CLAUDE/commands"
    link_children "$REPO/skills"   "$CLAUDE/skills"
    link_children "$REPO/rules"    "$CLAUDE/rules"

    CLAUDE_MD_BASE="${baseClaudeMdFile}"
    LOCAL_MD="$CLAUDE/CLAUDE.local.md"
    FINAL_MD="$CLAUDE/CLAUDE.md"

    ...   # CLAUDE.md rebuild from Task 3 unchanged
  '' + mcpActivation);
```

The two important syntactic changes:
1. The whole RHS of the assignment is now wrapped in `( ... + mcpActivation)`.
2. The closing `''` of the body is followed by `+ mcpActivation` and then `);`.

- [ ] **Step 4: Build and verify the no-op default**

```bash
home-manager build --flake .#chin39@vm-nix
```

Expected: builds. Since `mcpServers` defaults to `{}` and isn't passed by `home.nix`, the `mcpActivation` is empty:

```bash
grep -c 'CLAUDE_JSON=' /home/chin39/shell-config/result/activate
```

Expected: `0`.

```bash
grep -c 'mcpServers' /home/chin39/shell-config/result/activate
```

Expected: `0`.

- [ ] **Step 5: Apply (still a no-op) and confirm `~/.claude.json` untouched**

```bash
[ -f ~/.claude.json ] && cp ~/.claude.json /tmp/claude-json-before.json || echo 'no ~/.claude.json before switch'
home-manager switch --flake .#chin39@vm-nix
[ -f ~/.claude.json ] && diff /tmp/claude-json-before.json ~/.claude.json && echo 'unchanged' || echo 'changed or absent'
```

Expected: either both echo `no ~/.claude.json before switch` and `changed or absent` (file genuinely doesn't exist on this host), or `unchanged`. Anything else means the no-op contract is broken.

- [ ] **Step 6: Active-path smoke test (temporarily set a fake server)**

This is a one-off check to prove the merge works end-to-end. We mutate `home.nix`, build, apply, verify, then revert.

Edit `home-manager/home.nix:78-86` and add a temporary `mcpServers` arg:

```nix
  ++ lib.optionals (!smallNode) [
    (import ./programs/claude-code {
      inherit lib pkgs config hostname;
      source = inputs.everything-claude-code;
      extraInstructions = "";
      # TEMPORARY for plan Task 4 Step 6 — will be removed before commit.
      mcpServers = {
        smoke-test = {
          command = "echo";
          args = [ "ok" ];
        };
      };
    })
  ]
```

Then:

```bash
home-manager switch --flake .#chin39@vm-nix
${pkgs.jq:-jq} '.mcpServers."smoke-test"' ~/.claude.json
```

Expected: prints `{ "command": "echo", "args": ["ok"] }`.

If `~/.claude.json` had pre-existing top-level keys (e.g. `userID`, `oauthAccount`), confirm they survived the merge:

```bash
jq 'keys' ~/.claude.json
```

Expected: includes `mcpServers` plus any pre-existing keys; nothing got dropped.

Now revert the temporary edit:

```bash
git -C /home/chin39/shell-config checkout home-manager/home.nix
```

And clean the test entry from `~/.claude.json`:

```bash
[ -f ~/.claude.json ] && jq 'del(.mcpServers."smoke-test")' ~/.claude.json > /tmp/cj.tmp && mv /tmp/cj.tmp ~/.claude.json
```

Re-run the build to confirm the revert is good:

```bash
home-manager switch --flake .#chin39@vm-nix
grep -c 'CLAUDE_JSON=' /home/chin39/shell-config/result/activate
```

Expected: `0` again.

- [ ] **Step 7: Commit**

```bash
git -C /home/chin39/shell-config add home-manager/programs/claude-code/default.nix
git -C /home/chin39/shell-config commit -m "$(cat <<'EOF'
feat(claude-code): add declarative mcpServers option

- new module arg `mcpServers ? {}` flows into ~/.claude.json via a jq
  --slurpfile merge run only when non-empty
- defaults to {} so existing hosts are unchanged; ~/.claude.json runtime
  state is preserved when the option is unset
- preemptive surface for local MCP servers (filesystem, sqlite, etc.)

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>
EOF
)"
```

---

## Task 5: `extraHooks` option with per-event concat

**Files:**
- Modify: `home-manager/programs/claude-code/default.nix`

- [ ] **Step 1: Add the `extraHooks` arg**

Add `extraHooks ? { },` to the module signature, between `mcpServers ? { },` and `extraInstructions ? "",`:

```nix
{
  config,
  lib,
  pkgs,
  hostname,
  source,
  mcpServers ? { },
  extraHooks ? { },
  extraInstructions ? "",
  ...
}:
```

- [ ] **Step 2: Replace the inline hooks literal with a `defaultHooks + extraHooks` merge**

Find the `settings = { ... }` block in `default.nix`. The current `hooks = { ... };` field is inline. Replace the relevant portion:

```nix
  settings = {
    hooks = {
      Stop = [
        {
          hooks = [
            {
              type = "command";
              command = "${config.home.homeDirectory}/.claude/hooks/verify-complete.sh";
              timeout = 300;
              statusMessage = "Verifying task completion...";
            }
          ];
        }
      ];
      PreToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = "${config.home.homeDirectory}/.claude/hooks/block-destructive.sh";
            }
          ];
        }
      ];
    };
    enabledPlugins = { ... };
    ...
  };
```

Restructure: lift the hooks definition into the existing `let` block, expose it under the name `defaultHooks`, then merge with `extraHooks`. After the change, the `let` block has:

```nix
  defaultHooks = {
    Stop = [
      {
        hooks = [
          {
            type = "command";
            command = "${config.home.homeDirectory}/.claude/hooks/verify-complete.sh";
            timeout = 300;
            statusMessage = "Verifying task completion...";
          }
        ];
      }
    ];
    PreToolUse = [
      {
        matcher = "Bash";
        hooks = [
          {
            type = "command";
            command = "${config.home.homeDirectory}/.claude/hooks/block-destructive.sh";
          }
        ];
      }
    ];
  };

  mergedHooks =
    (lib.mapAttrs
      (event: defaults: defaults ++ (extraHooks.${event} or [ ]))
      defaultHooks)
    // (lib.removeAttrs extraHooks (lib.attrNames defaultHooks));
```

And the `settings` attrset's `hooks` field becomes simply:

```nix
    hooks = mergedHooks;
```

The merge semantics:
- For events present in `defaultHooks` (i.e. `Stop`, `PreToolUse`): concat `defaults ++ (extras for that event)`. The built-in entries are always preserved.
- For events only in `extraHooks` (e.g. `PostToolUse`, `UserPromptSubmit`): pass through as-is.

`lib.removeAttrs extraHooks (lib.attrNames defaultHooks)` is the second half of the merge — it isolates extras-only events so they're not double-counted.

- [ ] **Step 3: Build and verify the no-op default**

```bash
home-manager build --flake .#chin39@vm-nix
${pkgs.jq:-jq} '.hooks' /home/chin39/shell-config/result/home-files/.claude/settings.json
```

Expected output (key-order may differ; values must match):

```json
{
  "PreToolUse": [
    {
      "hooks": [
        {
          "command": "/home/chin39/.claude/hooks/block-destructive.sh",
          "type": "command"
        }
      ],
      "matcher": "Bash"
    }
  ],
  "Stop": [
    {
      "hooks": [
        {
          "command": "/home/chin39/.claude/hooks/verify-complete.sh",
          "statusMessage": "Verifying task completion...",
          "timeout": 300,
          "type": "command"
        }
      ]
    }
  ]
}
```

If anything is missing (especially the `Stop` and `PreToolUse` defaults), the merge logic in Step 2 is wrong — go back and recheck.

- [ ] **Step 4: Active-path smoke test (temporarily inject extras)**

Edit `home-manager/home.nix:78-86`:

```nix
  ++ lib.optionals (!smallNode) [
    (import ./programs/claude-code {
      inherit lib pkgs config hostname;
      source = inputs.everything-claude-code;
      extraInstructions = "";
      # TEMPORARY for plan Task 5 Step 4 — will be removed before commit.
      extraHooks = {
        # appends to the existing Stop entries (verify-complete.sh stays)
        Stop = [
          {
            hooks = [ { type = "command"; command = "/usr/bin/true"; } ];
          }
        ];
        # brand-new event group
        PostToolUse = [
          {
            matcher = "Edit";
            hooks = [ { type = "command"; command = "/usr/bin/true"; } ];
          }
        ];
      };
    })
  ]
```

Build and inspect:

```bash
home-manager build --flake .#chin39@vm-nix
${pkgs.jq:-jq} '.hooks' /home/chin39/shell-config/result/home-files/.claude/settings.json
```

Expected:
- `Stop` array has TWO entries: the original `verify-complete.sh` block AND the new `/usr/bin/true` block.
- `PostToolUse` exists with one entry: `matcher: "Edit"` plus the `/usr/bin/true` hook.
- `PreToolUse` is unchanged (one entry, the `block-destructive.sh` matcher Bash).

If `Stop` only has the new entry (the original was replaced), the merge is using `//` instead of concat — recheck Step 2's `lib.mapAttrs` line.

- [ ] **Step 5: Revert the temporary edit**

```bash
git -C /home/chin39/shell-config checkout home-manager/home.nix
home-manager build --flake .#chin39@vm-nix
${pkgs.jq:-jq} '.hooks | keys' /home/chin39/shell-config/result/home-files/.claude/settings.json
```

Expected: `["PreToolUse", "Stop"]` — back to the no-op default.

- [ ] **Step 6: Apply and confirm hooks still trigger live**

```bash
home-manager switch --flake .#chin39@vm-nix
test -x ~/.claude/hooks/verify-complete.sh && test -x ~/.claude/hooks/block-destructive.sh && echo 'hooks still executable'
```

Expected: `hooks still executable`.

To smoke-test the PreToolUse Bash hook end-to-end: run a destructive command inside Claude Code (e.g., `rm -rf /tmp/some-fake-dir`). The hook should block it. This is a manual check; if the executor can't run an interactive Claude session, skip and rely on the JSON inspection in Steps 3-4.

- [ ] **Step 7: Commit**

```bash
git -C /home/chin39/shell-config add home-manager/programs/claude-code/default.nix
git -C /home/chin39/shell-config commit -m "$(cat <<'EOF'
feat(claude-code): add extraHooks option with per-event concat semantics

- new module arg `extraHooks ? {}` lets callers add hook entries for any
  event without losing built-in defaults
- existing Stop+PreToolUse(Bash) entries become defaultHooks; mergedHooks
  concatenates per-event so extras append instead of replace
- events not in defaults (PostToolUse, UserPromptSubmit, etc.) pass through
  as-is

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>
EOF
)"
```

---

## Task 6: Final verification pass

**Files:** none modified. This task is a holistic check that all four extensions cohabitate.

- [ ] **Step 1: Re-evaluate from scratch**

```bash
home-manager build --flake .#chin39@vm-nix
```

Expected: succeeds.

- [ ] **Step 2: Run the spec's verification checklist**

| Check | Command | Expected |
|---|---|---|
| `~/.claude/CLAUDE.md` is a regular file | `[ -f ~/.claude/CLAUDE.md ] && [ ! -L ~/.claude/CLAUDE.md ] && echo ok` | `ok` |
| Local seed exists, starts with `<!--` | `head -c 4 ~/.claude/CLAUDE.local.md` | `<!--` |
| Symlink farm targets the store | `readlink ~/.claude/agents/code-reviewer.md \| head -c 11` | `/nix/store/` |
| No broken legacy symlinks | `find ~/.claude/{agents,commands,skills,rules} -maxdepth 1 -type l ! -exec test -e {} \; -print` | empty |
| `mcpServers` no-op | `grep -c CLAUDE_JSON= ./result/activate` | `0` |
| Default hooks intact | `jq '.hooks \| keys' ./result/home-files/.claude/settings.json` | `["PreToolUse","Stop"]` |
| `Stop` hook has verify-complete.sh | `jq -r '.hooks.Stop[0].hooks[0].command' ./result/home-files/.claude/settings.json` | `/home/chin39/.claude/hooks/verify-complete.sh` |
| `PreToolUse` hook has block-destructive.sh | `jq -r '.hooks.PreToolUse[0].hooks[0].command' ./result/home-files/.claude/settings.json` | `/home/chin39/.claude/hooks/block-destructive.sh` |
| 11 plugins enabled | `jq '.enabledPlugins \| length' ./result/home-files/.claude/settings.json` | `11` |

- [ ] **Step 3: Sentinel-file preservation test**

```bash
touch ~/.claude/agents/_local-test.md
home-manager switch --flake .#chin39@vm-nix
[ -f ~/.claude/agents/_local-test.md ] && echo 'sentinel preserved' && rm ~/.claude/agents/_local-test.md
```

Expected: `sentinel preserved`. Confirms the symlink farm's "don't clobber non-symlink files" guard is intact.

- [ ] **Step 4: Run task-verifier**

Per user-scope CLAUDE.md completion protocol:

> Delegate to the `task-verifier` subagent with a one-line summary of what you believe is done. Wait for its VERIFIED/NOT_VERIFIED JSON.

Use the Agent tool with `subagent_type=task-verifier`. Summary line:

> "Extended the claude-code home-manager module with: pinned `everything-claude-code` flake input replacing the imperative clone, switch-time `~/.claude/CLAUDE.md` rebuild that appends `~/.claude/CLAUDE.local.md` (seeded with HTML-commented note on first run), declarative `mcpServers` jq-merge into `~/.claude.json`, and `extraHooks` option with per-event concat. All four are no-ops by default; sentinel and broken-symlink checks pass."

Provide the verifier with: spec path, plan path, list of modified files, and a request to read the final state of `default.nix` and the live `~/.claude/` to confirm.

If `NOT_VERIFIED`, address each item in `reason`, re-run the verification commands, and re-call.

- [ ] **Step 5: Final commit (if any cleanup edits were made during verification)**

If verification surfaced fixes:

```bash
git -C /home/chin39/shell-config add -p   # review carefully
git -C /home/chin39/shell-config commit -m "$(cat <<'EOF'
fix(claude-code): <specific fix from verification>

- <bullet describing the fix>

Signed-off-by: Ruowen Qin <chinqrw@gmail.com>
EOF
)"
```

If verification was clean, no commit needed.

- [ ] **Step 6: Hand back to user**

Report: spec satisfied, all six tasks committed, verifier returned VERIFIED, no auto-push performed (per user preference). User can `git push` when ready.

---

## Notes for the executor

- **Sandbox:** `nix flake update`, `home-manager build`, and `home-manager switch` need filesystem and network access outside Claude Code's default sandbox. If the harness uses Claude Code's sandbox and a command fails with SQLite/network errors, retry with `dangerouslyDisableSandbox: true`. This is normal for Nix work.
- **No `--no-verify` or `--no-gpg-sign`:** The user's settings have hooks/sign-off conventions. Do not skip them. If a pre-commit hook fails, fix the cause; don't bypass.
- **Atomic commits per task:** Each Task ends in exactly one commit covering only that task's changes. The smoke-test edits in Tasks 4 and 5 must be reverted before committing — they're scaffolding, not the deliverable.
- **`pkgs.jq:-jq`:** If your shell doesn't have `jq` on `PATH`, use the absolute path from the build output, e.g., `nix shell nixpkgs#jq -c jq ...`. The activation script always uses the Nix-store `jq` regardless.
- **If a step fails:** stop. Don't paper over with skips or `|| true`. The user wants root-cause fixes, not workarounds.
