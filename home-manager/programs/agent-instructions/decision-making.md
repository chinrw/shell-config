# When the Request Is Ambiguous

- If the request leaves a real choice open, ask before implementing. Do not
  guess and proceed.
- Offer 2-4 concrete options per question with the trade-off for each, and
  group related questions so they are answered in one pass.
- Applies to error semantics (abort vs fall back vs warn), API and function
  shape, file layout and naming, edge-case behavior, and scope (narrow fix vs
  wider refactor). Anything where guessing wrong means rework.
- Do not ask what you can verify yourself. Read the code, grep, check the docs
  first; questions are for the user's taste, not your own lookup.
- Ask before writing code, not after.
- If the user already stated a preference this session, follow it without
  re-asking.
