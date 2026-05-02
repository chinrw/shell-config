#!/usr/bin/env bash
# Stop-hook verifier for Claude Code.
# Flow: (1) honor stop_hook_active to avoid loops, (2) cheap bail-out when
# nothing changed, (3) run mechanical gates, (4) delegate to the task-verifier
# subagent, (5) block stop with a specific reason if anything is incomplete.

set -u
INPUT="$(cat)"

# Live-tail log file. `tail -f` this from another pane to watch progress
# during the 4–5 minute verifier run. Also goes to stderr (Ctrl-O post-hoc).
VERIFY_LOG="${CLAUDE_VERIFY_LOG:-$HOME/.cache/claude-verify/current.log}"
mkdir -p "$(dirname "$VERIFY_LOG")" 2>/dev/null || true
: > "$VERIFY_LOG"   # truncate at the start of each hook run

_log() {
  local ts
  ts="$(date +%H:%M:%S)"
  printf '%s %s\n' "$ts" "$*" >&2
  printf '%s %s\n' "$ts" "$*" >> "$VERIFY_LOG" 2>/dev/null
}

# ---------- 1. Infinite-loop guard ----------
# stop_hook_active is true on Claude's SECOND stop attempt after we blocked once.
ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"')"
COUNT_FILE="/tmp/claude-verify-${SESSION_ID}.count"

if [ "$ACTIVE" = "true" ]; then
  COUNT=$(( $(cat "$COUNT_FILE" 2>/dev/null || echo 0) + 1 ))
  echo "$COUNT" > "$COUNT_FILE"
  MAX="${VERIFY_MAX_CONTINUATIONS:-3}"
  # MAX=0 disables forced continuation entirely (escape hatch).
  if [ "$MAX" = "0" ] || [ "$COUNT" -ge "$MAX" ]; then
    _log "[verify] retry cap reached (${COUNT}/${MAX}); allowing stop"
    exit 0
  fi
  _log "[verify] continuation ${COUNT}/${MAX}"
fi

# ---------- 2. Plan-mode gate ----------
# Only run verification when the session finished a PLAN — detected by the
# ExitPlanMode tool use in the transcript (Claude calls it when the user
# approves a plan). Without that signal, this is a "normal" task and
# verification is skipped to avoid spending Opus on trivial work.
#
#   VERIFY_FORCE=1   verify anyway (e.g. ad-hoc audit of a non-planned task)
#   VERIFY_SKIP=1    skip unconditionally (escape hatch during iterative work)
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // "."')"
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""')"

if [ "${VERIFY_SKIP:-0}" = "1" ]; then
  _log "[verify] VERIFY_SKIP=1; skipping"
  exit 0
fi
if [ "${VERIFY_FORCE:-0}" != "1" ]; then
  if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] || \
     ! grep -qE '"name"[[:space:]]*:[[:space:]]*"ExitPlanMode"' "$TRANSCRIPT" 2>/dev/null; then
    _log "[verify] non-planned task (no ExitPlanMode in transcript); skipping"
    _log "[verify] set VERIFY_FORCE=1 to verify non-planned tasks on demand"
    exit 0
  fi
  _log "[verify] planned task detected (ExitPlanMode found in transcript)"
fi

# ---------- 3. Cheap bail-out: nothing to verify ----------
# Even for planned tasks, skip if nothing was actually edited this session.
# This is defense in depth: a planned task that ended without edits is a no-op.

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] || \
   ! grep -qE '"name"[[:space:]]*:[[:space:]]*"(Edit|Write|MultiEdit)"' "$TRANSCRIPT" 2>/dev/null; then
  # Second signal: git-clean repos also need no verification.
  if [ -d "$CWD/.git" ]; then
    if [ -z "$(cd "$CWD" && git status --porcelain 2>/dev/null)" ]; then
      _log "[verify] no edits in session; git clean — skipping"
      exit 0
    fi
  else
    _log "[verify] no edits in session — skipping"
    exit 0
  fi
fi

# ---------- 3. Mechanical gates (cheap, deterministic) ----------
_log "[verify] running mechanical gates (tsc/tests/ruff/mypy/pytest)…"
FAIL_REASONS=()
cd "$CWD" 2>/dev/null || true

if [ -f package.json ]; then
  # Only run tsc when the project actually has TypeScript. `package.json`
  # alone is not proof — many Python/mixed repos ship a tiny JS harness.
  # Without this guard, `npx --no-install tsc` resolves to the unrelated
  # `tsc@2.0.4` npm package (a process manager) and blocks forever.
  _has_ts() {
    [ -f tsconfig.json ] || [ -f tsconfig.base.json ] || \
      find . -maxdepth 4 -type f \( -name '*.ts' -o -name '*.tsx' \) \
        -not -path '*/node_modules/*' -not -path '*/.venv/*' \
        -print -quit 2>/dev/null | grep -q .
  }
  # All tool invocations MUST capture stdout to a file (not leak to the hook's
  # stdout), because we emit JSON on stdout at the end. Claude Code parses the
  # hook's stdout as JSON — any stray tool output before the JSON breaks the
  # parse, and mechanical-block decisions silently become no-ops.
  if _has_ts; then
    if [ -x node_modules/.bin/tsc ]; then
      node_modules/.bin/tsc --noEmit >/tmp/tsc.out 2>/tmp/tsc.err || \
        FAIL_REASONS+=("TypeScript errors: $(cat /tmp/tsc.out /tmp/tsc.err 2>/dev/null | head -20)")
    elif npx --no-install --package=typescript -- tsc --noEmit >/tmp/tsc.out 2>/tmp/tsc.err; then
      :  # passed
    else
      # Couldn't run tsc at all — warn, don't block. Missing dep is a setup
      # issue, not a completion failure.
      _log "[verify-complete] tsc not installed; skipping TypeScript check"
    fi
  fi

  # Only run `npm test` when a test runner is actually installed locally.
  # A declared-but-uninstalled devDependency produces a "vitest: command
  # not found" that blocks stop without any actionable signal.
  if [ -d node_modules ] && ( [ -x node_modules/.bin/vitest ] || [ -x node_modules/.bin/jest ] || [ -x node_modules/.bin/mocha ] ); then
    if ! npm test --silent >/tmp/test.out 2>/tmp/test.err; then
      FAIL_REASONS+=("Tests failing: $(cat /tmp/test.out /tmp/test.err 2>/dev/null | tail -30)")
    fi
  elif [ -f package.json ] && grep -qE '"(vitest|jest|mocha)"' package.json 2>/dev/null; then
    _log "[verify-complete] JS tests declared but node_modules missing; run 'npm install' to enable"
  fi
fi

if [ -f pyproject.toml ] || [ -f setup.py ]; then
  command -v ruff >/dev/null && { ruff check . >/tmp/ruff.out 2>/tmp/ruff.err || FAIL_REASONS+=("Ruff: $(cat /tmp/ruff.out /tmp/ruff.err 2>/dev/null | head -20)"); }
  # Prefer pyrefly over mypy when both are installed — a project that ships
  # `[tool.pyrefly]` + `# pyrefly: ignore` markers has chosen its type
  # checker, and running bare mypy would flood with false positives.
  # Bare `pyrefly check` (no target) honors pyproject.toml's
  # `[tool.pyrefly].project_includes`; explicit `.` would override it.
  if command -v pyrefly >/dev/null; then
    pyrefly check >/tmp/pyrefly.out 2>/tmp/pyrefly.err || FAIL_REASONS+=("Pyrefly: $(cat /tmp/pyrefly.out /tmp/pyrefly.err 2>/dev/null | head -20)")
  elif command -v mypy >/dev/null; then
    mypy . >/tmp/mypy.out 2>/tmp/mypy.err || FAIL_REASONS+=("Mypy: $(cat /tmp/mypy.out /tmp/mypy.err 2>/dev/null | head -20)")
  fi
  command -v pytest >/dev/null && { pytest -x --tb=short >/tmp/pyt.out 2>/tmp/pyt.err || FAIL_REASONS+=("Pytest: $(cat /tmp/pyt.out /tmp/pyt.err 2>/dev/null | tail -30)"); }
fi

if [ "${#FAIL_REASONS[@]}" -gt 0 ]; then
  _log "[verify] mechanical gates FAILED (${#FAIL_REASONS[@]} issue(s)); blocking stop"
  REASON=$(printf '%s\n' "${FAIL_REASONS[@]}")
  # Truncate to ~9 KB so Claude Code doesn't convert the reason into a preview+file.
  REASON=$(printf '%s' "$REASON" | head -c 9000)
  SUMMARY="✗ Verifier blocked: ${#FAIL_REASONS[@]} mechanical check(s) failed"
  jq -n --arg r "$REASON" --arg s "$SUMMARY" \
    '{decision:"block", reason:("Mechanical checks failed. Fix before stopping:\n" + $r), systemMessage:$s}'
  exit 0
fi
_log "[verify] mechanical gates passed"

# ---------- 4. LLM verifier via headless subagent ----------
# The verifier is the expensive step (Opus call + full-repo traversal). Skip
# it when the repo state hasn't changed since the last VERIFIED pass. Cache
# key: HEAD SHA + short hash of the uncommitted diff. Any commit or edit
# invalidates the cache; a no-op Stop after we already verified is free.
VERIFY_CACHE_DIR="${CLAUDE_VERIFY_CACHE_DIR:-$HOME/.cache/claude-verify}"
mkdir -p "$VERIFY_CACHE_DIR" 2>/dev/null || true

_state_id() {
    # Cheap, deterministic ID. Empty string means "no git info available".
    if [ -d "$CWD/.git" ] && command -v git >/dev/null; then
        local head diff_hash
        head="$(cd "$CWD" && git rev-parse HEAD 2>/dev/null || echo nohead)"
        diff_hash="$(cd "$CWD" && git diff HEAD 2>/dev/null | sha256sum 2>/dev/null | cut -c1-12)"
        printf '%s|%s' "$head" "$diff_hash"
    fi
}

VERIFY_STATE_ID="$(_state_id)"
# Key the cache by absolute CWD so multiple worktrees don't clash.
VERIFY_CACHE_KEY="$(printf '%s' "$CWD" | sha256sum | cut -c1-16)"
VERIFY_CACHE_FILE="$VERIFY_CACHE_DIR/$VERIFY_CACHE_KEY.sha"

if [ -n "$VERIFY_STATE_ID" ] && [ -f "$VERIFY_CACHE_FILE" ] && \
   [ "$(cat "$VERIFY_CACHE_FILE" 2>/dev/null)" = "$VERIFY_STATE_ID" ]; then
    _log "[verify] state unchanged since last VERIFIED pass — skipping LLM call"
    exit 0
fi

LAST_MSG="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // ""')"

# Locate the active plan file. Claude Code's plan mode writes approved plans
# to ~/.claude/plans/<random-name>.md; we take the most recently modified one.
# Falls back to in-repo PLAN.md / .plans/current.md for project-scoped plans.
_find_plan_file() {
  local candidate
  for candidate in "$CWD/PLAN.md" "$CWD/.plans/current.md" "$CWD/TODO.md"; do
    [ -f "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  done
  find "$HOME/.claude/plans" -maxdepth 1 -name '*.md' -type f -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -1 | cut -d' ' -f2-
}
PLAN_FILE="$(_find_plan_file)"
if [ -n "$PLAN_FILE" ]; then
  _log "[verify] plan file: $PLAN_FILE"
else
  _log "[verify] no plan file found — verifier will fall back to transcript"
fi

VERIFIER_PROMPT=$(cat <<EOF
You are invoked as a Stop-hook verifier. Context:
- Session transcript: $TRANSCRIPT
- Working directory: $CWD
- Main agent's final message: $LAST_MSG
- Approved plan file: ${PLAN_FILE:-<none found; infer from transcript>}

The plan file is the source of truth for what should have been accomplished.
Read it in full, enumerate every concrete deliverable/task it specifies, and
check each one against the repo state. Do not trust the main agent's claim of
"done" without independent evidence on disk.

Return the exact JSON contract defined in your system prompt.
EOF
)

# Stream subagent tool events to stderr (Ctrl-O) AND the live-tail log file.
# The full event stream is captured to $STREAM_LOG for verdict extraction.
_log "[verify] ────────── task-verifier ──────────"
_log "[verify] tail -f $VERIFY_LOG  ← run in another pane for live progress"
STREAM_LOG="$(mktemp -t verifier-stream.XXXXXX)"

set -o pipefail
MAX_THINKING_TOKENS="${VERIFY_THINKING_BUDGET:-32000}" \
claude -p \
  --agent task-verifier \
  --model "claude-opus-4-6[1M]" \
  --output-format stream-json \
  --verbose \
  --permission-mode acceptEdits \
  "$VERIFIER_PROMPT" 2>/tmp/verifier.err \
  | tee "$STREAM_LOG" \
  | jq --unbuffered -r '
      select(.type=="assistant")
      | .message.content[]?
      | select(.type=="tool_use")
      | "[verify] ↪ \(.name) \((.input.command // .input.pattern // .input.file_path // .input.description // (.input|tostring))|tostring|.[0:100])"
    ' | tee -a "$VERIFY_LOG" >&2
VERIFIER_EXIT=$?
set +o pipefail

if [ "$VERIFIER_EXIT" -ne 0 ]; then
  _log "[verify] subagent exited non-zero (${VERIFIER_EXIT}); see /tmp/verifier.err"
  VERDICT='{"verdict":"ERROR"}'
else
  # Pull the final `result` event's result field and extract the inner JSON
  # object. The agent sometimes wraps the object in ```json fences, adds
  # prose around it, or both — handle all three via Python.
  VERDICT=$(python3 - "$STREAM_LOG" <<'PYEOF' 2>/dev/null
import json, re, sys
try:
    with open(sys.argv[1]) as f:
        result_text = ""
        for line in f:
            try:
                evt = json.loads(line)
                if evt.get("type") == "result":
                    result_text = evt.get("result", "") or ""
            except Exception:
                continue
    s = result_text.strip()
    if not s:
        sys.exit(0)
    # Strip a markdown code fence if present.
    m = re.search(r"```(?:json)?\s*(.+?)\s*```", s, re.DOTALL)
    if m:
        s = m.group(1).strip()
    # If what's left is parseable JSON, emit it; otherwise fall through.
    try:
        obj = json.loads(s)
        print(json.dumps(obj))
        sys.exit(0)
    except Exception:
        pass
    # Last resort: find the first balanced {...} containing "verdict".
    depth = 0
    start = -1
    for i, ch in enumerate(s):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                candidate = s[start:i+1]
                if '"verdict"' in candidate:
                    try:
                        obj = json.loads(candidate)
                        print(json.dumps(obj))
                        sys.exit(0)
                    except Exception:
                        start = -1
except Exception:
    pass
PYEOF
)
  [ -z "$VERDICT" ] && VERDICT='{"verdict":"ERROR"}'
fi

_log "[verify] raw verdict: $VERDICT"
rm -f "$STREAM_LOG"

VERDICT_STATUS=$(printf '%s' "$VERDICT" | jq -r '.result // .verdict // "ERROR"' 2>/dev/null)
_log "[verify] verdict: ${VERDICT_STATUS:-ERROR}"

# ---------- 5. Decision ----------
if echo "$VERDICT_STATUS" | grep -qiE 'VERIFIED|PASS|^ok$'; then
  # Cache the pass so the next Stop with unchanged state skips step 4.
  [ -n "$VERIFY_STATE_ID" ] && printf '%s' "$VERIFY_STATE_ID" > "$VERIFY_CACHE_FILE" 2>/dev/null || true
  _log "[verify] ✓ allowing stop"
  # systemMessage gives the user a one-line positive confirmation in the
  # transcript — much better UX than the spinner silently disappearing.
  jq -n '{systemMessage:"✓ Task verified"}'
  exit 0
fi
_log "[verify] ✗ blocking stop; main agent will continue"

REASON=$(printf '%s' "$VERDICT" | jq -r '.reason // .result' 2>/dev/null)
[ -z "$REASON" ] && REASON="Verifier could not confirm completion. Continue working and address gaps."
# Truncate to ~9 KB so long NOT_VERIFIED reasons don't get replaced by a preview.
REASON=$(printf '%s' "$REASON" | head -c 9000)
# Short user-visible summary for the transcript; first line or first 80 chars.
SUMMARY=$(printf '%s' "$REASON" | head -n 1 | head -c 80)
[ -n "$SUMMARY" ] && SUMMARY="✗ Verifier blocked: $SUMMARY" || SUMMARY="✗ Verifier blocked stop"

jq -n --arg r "$REASON" --arg s "$SUMMARY" '{decision:"block", reason:$r, systemMessage:$s}'
exit 0
