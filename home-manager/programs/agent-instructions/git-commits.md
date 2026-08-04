# Git Commits

- Subject: `<prefix>: <description>`, imperative mood, <= 72 chars, no trailing
  period.
- Match the prefix style already in `git log`. Some repos use a scope
  (`zellij:`, `macos:`), others a conventional type (`feat:`, `fix:`). Read the
  last ~20 subjects before writing the first one.
- No existing convention: use the conventional type — feat, fix, refactor,
  docs, test, chore, perf, ci.
- Body is optional. A change the subject already explains gets no body — adding
  one to look thorough is noise.
- Write a body only for what the subject cannot hold: a non-obvious cause, a
  constraint, a rejected alternative, a failure mode a future `git bisect`
  would need.
- When there is a body: bullet points, one change or one reason per bullet. Not
  a paragraph, not a line-by-line replay of the diff. Past ~6 bullets, the
  commit usually wants to be two commits.
- Last line of every commit message: `Signed-off-by: Name <email>`, taken from
  the current repo's git config.
- No agent attribution and no co-author trailers.
