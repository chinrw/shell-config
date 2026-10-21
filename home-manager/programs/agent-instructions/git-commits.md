# Git Commits

- Read recent commit messages before writing the first one. Follow the
  repo's established subject and body format, including formats without a
  prefix. Existing conventions take precedence over the defaults below.
- Default subject: `<prefix>: <description>`, imperative mood, <= 72 chars,
  no trailing period. Use feat, fix, refactor, docs, test, chore, perf, or ci.
- Write a body only for what the subject cannot explain: a non-obvious cause, a
  constraint, a rejected alternative, a failure mode a future `git bisect`
  would need.
- Default body format: bullet points, one change or one reason per bullet.
  Do not replay the diff line by line. Split unrelated changes into separate
  commits.
- Last line of every commit message: `Signed-off-by: Name <email>`, taken from
  the current repo's git config.
- No agent attribution and no co-author trailers.
