# Git Commits

- Read the last ~20 commit messages before writing the first one. Follow the
  repo's established subject and body format, including formats without a
  prefix. Existing conventions take precedence over the defaults below.
- Default subject: `<prefix>: <description>`, imperative mood, <= 72 chars,
  no trailing period. Use feat, fix, refactor, docs, test, chore, perf, or ci.
- Body is optional. A change the subject already explains gets no body — adding
  one to look thorough is noise.
- Write a body only for what the subject cannot hold: a non-obvious cause, a
  constraint, a rejected alternative, a failure mode a future `git bisect`
  would need.
- Default body format: bullet points, one change or one reason per bullet. Not
  a paragraph, not a line-by-line replay of the diff. Past ~6 bullets, the
  commit usually wants to be two commits.
- Last line of every commit message: `Signed-off-by: Name <email>`, taken from
  the current repo's git config.
- No agent attribution and no co-author trailers.
