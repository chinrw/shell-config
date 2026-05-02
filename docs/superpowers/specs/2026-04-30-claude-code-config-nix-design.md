# Design: Extending the claude-code home-manager module

**Status:** Brainstormed, not yet implemented.
**Date:** 2026-04-30
**Scope:** `home-manager/programs/claude-code/`, `flake.nix` (one input add), `home-manager/home.nix` (one new arg pass-through).

## Context

The claude-code home-manager module landed earlier today. It manages
`~/.claude/{settings.json,CLAUDE.md,hooks/}` declaratively and maintains
per-item symlink farms in `~/.claude/{agents,commands,skills,rules}/` from a
copy of `affaan-m/everything-claude-code` cloned imperatively into
`~/Documents/play/`.

This spec covers four extensions identified in a brainstorm session:

1. Replace the imperative `git clone` of `everything-claude-code` with a
   pinned flake input.
2. Allow per-host CLAUDE.md additions via a host-local
   `~/.claude/CLAUDE.local.md` that the module appends on every
   `home-manager switch`.
3. Add a declarative `mcpServers` option (default empty) for user-scope MCP
   servers. Done as a `jq` merge into `~/.claude.json` so we don't clobber
   Claude Code's own runtime state.
4. Add an `extraHooks` option that lets callers contribute hook entries for
   any event without losing the existing defaults.

Out of scope: refactoring to a `programs.claudeCode.*` option module. The
existing `import-with-args` shape is retained for consistency with every
other module under `home-manager/programs/`.

## Goals

After this lands:

- `nix flake update everything-claude-code` then `home-manager switch` is the
  full update path — no `git pull` of a working copy required.
- Editing `~/.claude/CLAUDE.local.md` and running `home-manager switch` makes
  the additions visible to Claude on the next session.
- Adding a local MCP server is one attribute in `home.nix`; same for adding
  a hook for a non-default event like `PostToolUse` or `UserPromptSubmit`.
- Hosts that don't pass any new options keep behaving exactly like today.

## Module surface

```nix
(import ./programs/claude-code {
  inherit lib pkgs config hostname;
  source = inputs.everything-claude-code;   # NEW: store path of the flake input
  extraInstructions = "";                   # unchanged
  mcpServers = { };                         # NEW: { name = { command, args, env, ... }; }
  extraHooks = { };                         # NEW: { Stop = [...]; PostToolUse = [...]; ... }
})
```

All new args have empty/no-op defaults. The current call site in
`home-manager/home.nix` only needs `source = inputs.everything-claude-code;`
added.

## 1. Flake input replacing the imperative clone

`flake.nix` gains:

```nix
inputs.everything-claude-code = {
  url = "github:affaan-m/everything-claude-code";
  flake = false;
};
```

`flake.lock` pins the commit. Updating: `nix flake update everything-claude-code`.

`mkHome` in `lib/helpers.nix` already passes `inputs` via
`extraSpecialArgs`, so the module reaches it through `home.nix` without any
helper change.

The activation block in `default.nix` drops the `git clone` step entirely
and also moves its DAG gate from `writeBoundary` to `linkGeneration`. The
later gate matters for the CLAUDE.md rebuild in §2: home-manager's orphan
cleanup must finish removing the old `~/.claude/CLAUDE.md` symlink before
the activation step writes the new real file at the same path. The
symlink-farm bits don't care which gate is used, so moving the whole entry
is fine.

```nix
home.activation.claudeCodeAssets = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
  REPO="${source}"
  CLAUDE="${config.home.homeDirectory}/.claude"

  link_children() { ... }   # unchanged structure

  link_children "$REPO/agents"   "$CLAUDE/agents"
  link_children "$REPO/commands" "$CLAUDE/commands"
  link_children "$REPO/skills"   "$CLAUDE/skills"
  link_children "$REPO/rules"    "$CLAUDE/rules"
'';
```

### Sweep correctness

The current sweep matches `-lname "$REPO/*"`. Because `$REPO` changes from
`~/Documents/play/everything-claude-code` to a `/nix/store/...` path, old
symlinks would not match and would be left as broken links after the first
switch. Broaden the sweep:

```bash
${pkgs.findutils}/bin/find "$dst" -maxdepth 1 -type l \
  \( -lname "$REPO/*" -o -lname "*/everything-claude-code/*" \) \
  -exec sh -c '[ ! -e "$1" ] && rm "$1"' _ {} \;
```

The added `*/everything-claude-code/*` glob catches the legacy
`~/Documents/play/everything-claude-code/...` targets so the first switch
cleans them up. Fresh hosts only ever match the `$REPO/*` half.

`~/Documents/play/everything-claude-code/` is no longer load-bearing once
this lands. The activation script does not delete it; the user can keep it
for hand-editing or remove it manually.

## 2. CLAUDE.md rebuild + CLAUDE.local.md seeding

Today `~/.claude/CLAUDE.md` is a `home.file`-managed read-only symlink.
After: it is a regular file written by the activation script as
`base + extra + local`. `~/.claude/CLAUDE.local.md` is the host-local
editable file.

### Module changes

1. Drop `home.file.".claude/CLAUDE.md"` from the module.
2. Materialize the base content (with per-host extra already folded in) as
   a Nix-store file:
   ```nix
   let
     baseClaudeMd = builtins.readFile ./CLAUDE.md;
     withHostExtra =
       if extraInstructions == "" then baseClaudeMd
       else baseClaudeMd + "\n\n## Host-specific (${hostname})\n\n" + extraInstructions;
     baseClaudeMdFile = pkgs.writeText "claude-md-base" withHostExtra;
   in ...
   ```
   The host-specific footer is part of the "base" the activation script
   appends `CLAUDE.local.md` onto. From the activation script's point of
   view there is one Nix-side file (`baseClaudeMdFile`) and one local file.
3. Add an activation step inside the same `claudeCodeAssets` entry (now
   gated on `linkGeneration`):
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
     rm "$FINAL_MD"
   fi

   TMP_MD="$(mktemp)"
   {
     cat "$CLAUDE_MD_BASE"
     if [ -s "$LOCAL_MD" ]; then
       printf '\n\n## Local additions (%s)\n\n' "${hostname}"
       cat "$LOCAL_MD"
     fi
   } > "$TMP_MD"
   mv "$TMP_MD" "$FINAL_MD"
   ```

### Properties

- **Idempotent:** Re-switching produces the same `CLAUDE.md` byte-for-byte.
- **Atomic write:** `mktemp + mv` so a Claude session reading mid-switch
  sees either the old file or the new file, never a partial.
- **First switch transition:** an existing `home.file`-managed symlink at
  `~/.claude/CLAUDE.md` is detected (`-L`) and removed before the rebuild.
- **Seed text is HTML-commented** so a fresh-host `CLAUDE.md` is
  functionally identical to a host where `CLAUDE.local.md` doesn't exist.
- **Edit flow:** edit `CLAUDE.local.md` → `home-manager switch` → fresh
  `CLAUDE.md`.

## 3. mcpServers option

Claude Code reads user-scope MCP servers from `~/.claude.json` under
`.mcpServers`. Project-scope `<project>/.mcp.json` is out of scope for this
module — projects manage their own.

`~/.claude.json` is also where Claude Code stashes login state, last-update
checks, and other runtime data. We must not clobber it. Solution: a `jq`
merge in activation that only rewrites `.mcpServers`. The MCP config is
written to a Nix-store file and passed to `jq` via `--slurpfile` so we
never embed user-controlled JSON inside a shell-quoted string.

```nix
let
  mcpServersFile = pkgs.writeText "claude-mcp-servers.json"
    (builtins.toJSON mcpServers);

  mcpActivation = lib.optionalString (mcpServers != { }) ''
    CLAUDE_JSON="$HOME/.claude.json"
    TMP="$(mktemp)"
    if [ -f "$CLAUDE_JSON" ]; then
      ${pkgs.jq}/bin/jq --slurpfile m ${mcpServersFile} \
        '.mcpServers = $m[0]' "$CLAUDE_JSON" > "$TMP"
    else
      ${pkgs.jq}/bin/jq -n --slurpfile m ${mcpServersFile} \
        '{ mcpServers: $m[0] }' > "$TMP"
    fi
    mv "$TMP" "$CLAUDE_JSON"
  '';
in ...
```

`mcpActivation` is concatenated into the `claudeCodeAssets` activation
script. When `mcpServers = { }` the `optionalString` returns `""` and the
whole block disappears at Nix evaluation time — Claude's runtime state is
untouched.

Using `--slurpfile` (which reads JSON from a path) instead of `--argjson`
(which takes JSON inline) means the MCP config never travels through a
shell-quoted string, so user-supplied values containing literal apostrophes
or backslashes can't break the activation script.

Caller usage example (none today; preemptive):

```nix
mcpServers = {
  filesystem = {
    command = "npx";
    args = [ "-y" "@modelcontextprotocol/server-filesystem" "/home/chin39/Documents" ];
  };
};
```

## 4. extraHooks option

The current `settings.hooks` block is a hardcoded literal. The new shape
keeps the defaults intact and lets callers append per-event entries:

```nix
let
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
in
  settings = { ...; hooks = mergedHooks; ... };
```

Behavior: per-event concat. `extraHooks.Stop = [...]` appends to the
existing Stop entries (the verify-complete.sh hook is preserved).
`extraHooks.PostToolUse = [...]` becomes a brand-new event group. Callers
never accidentally lose defaults.

Caller usage example (none today; extension point):

```nix
extraHooks = {
  PostToolUse = [
    { matcher = "Edit"; hooks = [ { type = "command"; command = "/some/format-on-save.sh"; } ]; }
  ];
  UserPromptSubmit = [
    { hooks = [ { type = "command"; command = "/some/log-prompt.sh"; } ]; }
  ];
};
```

## 5. Migration and verification

### One-time on vm-nix when this lands

1. Add the flake input: `nix flake lock --update-input everything-claude-code`
   (or `nix flake update` after editing `flake.nix`).
2. `home-manager switch --flake .#chin39@vm-nix`. Activation:
   - Sweep deletes legacy `~/.claude/{agents,commands,skills,rules}/*`
     symlinks pointing at `~/Documents/play/everything-claude-code/...`.
   - New symlinks pointing at `${inputs.everything-claude-code}/...` are
     created.
   - The old `home.file`-managed `~/.claude/CLAUDE.md` symlink is removed
     and replaced with a real file built from base + local.
   - `~/.claude/CLAUDE.local.md` is seeded with the HTML-commented note.
3. `~/Documents/play/everything-claude-code/` becomes optional. Not removed
   automatically.

### Verification checklist

| Check | Command |
|---|---|
| Module evaluates | `home-manager build --flake .#chin39@vm-nix` |
| `~/.claude/CLAUDE.md` is a regular file | `[ -f ~/.claude/CLAUDE.md ] && [ ! -L ~/.claude/CLAUDE.md ]` |
| Base content present | `head -1 ~/.claude/CLAUDE.md` matches the module's CLAUDE.md |
| Local seed exists | `[ -f ~/.claude/CLAUDE.local.md ]` and starts with `<!--` |
| Local edits propagate | Append known string to local, rerun switch, `tail` shows it |
| Symlink farm targets store | `readlink ~/.claude/agents/code-reviewer.md` starts with `/nix/store/` |
| No broken legacy symlinks | `find ~/.claude/{agents,commands,skills,rules} -maxdepth 1 -type l ! -exec test -e {} \; -print` is empty |
| `mcpServers = {}` is a no-op | `~/.claude.json` either absent or unchanged from pre-switch |
| Hooks still wire | Trigger destructive bash → blocked. Finish a task → verify-complete.sh runs. |

### Risk register

| Risk | Mitigation |
|---|---|
| `~/.claude.json` clobber on switch | `jq` merge in activation; never `home.file` it |
| Stale symlinks point at old `~/Documents/play/...` location | Sweep glob matches both old and new source paths |
| Claude reads CLAUDE.md mid-rebuild | Atomic `mktemp + mv` write |
| User edits `~/.claude/CLAUDE.md` directly | Activation rebuilds and overwrites; seed text in `CLAUDE.local.md` documents that local edits go in `CLAUDE.local.md` |
| Flake input fetch fails offline | Nix uses cached store path; only `nix flake update` needs network |
| `extraHooks` collision with built-in defaults | Per-event concat semantics: extras append, never replace |

## Critical files

- Modified: `flake.nix` — one new input.
- Modified: `home-manager/home.nix` — `source = inputs.everything-claude-code;` added to the existing import.
- Modified: `home-manager/programs/claude-code/default.nix` —
  - drop `home.file.".claude/CLAUDE.md"`
  - add module args: `source`, `mcpServers`, `extraHooks`
  - extend `home.activation.claudeCodeAssets` with the CLAUDE.md rebuild,
    `CLAUDE.local.md` seed, broadened sweep glob, and `jq`-merge for
    `~/.claude.json`
  - rework `settings.hooks` to merge `defaultHooks` with `extraHooks`
- Unchanged: `home-manager/programs/claude-code/CLAUDE.md`,
  `home-manager/programs/claude-code/hooks/*` —
  their content remains the source of truth for the base CLAUDE.md and the
  two committed hook scripts.

## Resolved decisions

- Module shape: incremental import-with-args extension. (Not
  `programs.claudeCode.*` — explicitly skipped.)
- Vendor model: flake input pinned via `flake.lock`.
- CLAUDE.md rebuild trigger: `home-manager switch` only; no daemons or
  wrappers.
- `CLAUDE.local.md` seed text: HTML-commented so a fresh host's
  `CLAUDE.md` is functionally identical to one without a local file.
- `~/.claude.json` write strategy: `jq --slurpfile` merge over a Nix-store
  file path; never `home.file` clobber, never inline JSON in shell-quoted
  context.
- `extraHooks` merge semantics: per-event concat (extras append, defaults
  preserved).
- Activation DAG gate: `entryAfter [ "linkGeneration" ]` so the CLAUDE.md
  rebuild runs after home-manager finishes its own orphan cleanup of the
  prior generation's `home.file` symlink at that path.
