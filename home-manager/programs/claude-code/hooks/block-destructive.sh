#!/usr/bin/env bash
# PreToolUse hook. Blocks obviously destructive shell commands and sensitive
# file access. Exits 2 + writes reason to stderr so Claude sees it.
#
# Destructive patterns must appear at a command boundary (start of string, or
# after ;, &&, ||, |, or newline) so that benign strings like
# `echo "rm -rf x"` or `grep 'rm -rf' log` do NOT trip the block.

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')

if [ "$TOOL" = "Bash" ]; then
  CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
  # Prepend a synthetic boundary char so the regex anchor works at string start.
  CHECK="; $CMD"
  # Match dangerous command tokens only at a real command boundary.
  # rm recursive: -r, -R, -f, -F, or any mixed flag ending in any of those.
  if printf '%s' "$CHECK" | grep -qE '(^|;|&&|\|\||\|)[[:space:]]*(rm[[:space:]]+(-[a-zA-Z]*[rRfF]|--recursive|--force)|git[[:space:]]+push[[:space:]].*--force|git[[:space:]]+reset[[:space:]]+--hard|dd[[:space:]]+if=|mkfs([[:space:]]|\.))'; then
    echo "BLOCKED: destructive command pattern detected in: $CMD" >&2
    exit 2
  fi
  # Fork bomb: :(){ :|:& };:
  if printf '%s' "$CMD" | grep -qF ':(){ :|:& };:'; then
    echo "BLOCKED: fork bomb detected" >&2
    exit 2
  fi
  # Dangerous SQL DROPs in Bash commands (rare but severe).
  if printf '%s' "$CMD" | grep -qiE '\bDROP[[:space:]]+(TABLE|DATABASE|SCHEMA)\b'; then
    echo "BLOCKED: DROP statement in Bash command: $CMD" >&2
    exit 2
  fi
fi

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
for pat in ".env" ".env.local" ".env.production" "id_rsa" "credentials.json" ".git/"; do
  case "$FILE" in *"$pat"*)
    echo "BLOCKED: protected path $pat — do not read or write" >&2
    exit 2 ;;
  esac
done
exit 0
