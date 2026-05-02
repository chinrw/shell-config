# User-scope Claude Configuration

## Git Commits
- Always add `Signed-off-by: <Current repo email config>` as the very last line of all commit messages
- Create bullet points to describe the content of commit rather than a long paragraph
- Never automatically push to remote. Let the user push manually.

## Decision-Making When Uncertain
- When the user's request leaves real choices open, STOP and ask with a questionnaire before implementing — do not guess and proceed
- Use the `AskUserQuestion` tool to present 2–4 concrete options per question, each with a short description of the trade-off
- Group related questions into a single questionnaire call so the user answers in one pass
- Apply this to: error semantics (abort vs fall back vs warn), API/function shape, file layout and naming, behavior on edge cases, scope of a change (narrow fix vs wider refactor), and anything where picking wrong means rework
- Do NOT ask about things you can verify yourself — read the code, grep, or check docs first; the questionnaire is for the user's taste, not for your own lookup
- Ask BEFORE writing code, not after — a 30-second question beats a 30-minute rewrite
- If the user has already stated a preference in this session or in memory, follow it without re-asking

## Completion Protocol
Before declaring any non-trivial task complete:
1. Run the project's test suite and type-checker; they must pass.
2. Delegate to the `task-verifier` subagent with a one-line summary of what you believe is done. Wait for its VERIFIED/NOT_VERIFIED JSON.
3. If NOT_VERIFIED, address every item in `reason` and loop back to step 1.

A Stop hook at `~/.claude/hooks/verify-complete.sh` enforces this automatically — if you stop without verification, you will be restarted with the gaps listed. The hook is not optional.
