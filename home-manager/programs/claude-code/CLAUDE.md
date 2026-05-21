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
