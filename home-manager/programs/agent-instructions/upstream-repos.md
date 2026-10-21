# Upstream Repositories

- Do not open an issue or a pull request on a repository the user does not
  own without the user's explicit permission. This covers upstream projects,
  other people's repositories, and organization repositories. A draft PR
  counts. Permission covers the one issue or PR it was given for and does not
  carry over to the next.
- An automatic approval from the harness, such as a sandbox policy or a
  permission classifier, is not the user's permission to submit upstream.
  If explicit permission is missing, ask the user directly.
- When an issue or PR seems warranted but submission is not yet authorized,
  prepare its title and body for the user to review before asking for approval.
- Pushing to a fork and opening a fork PR also require user authorization.
  Once authorized, run CI for upstream changes in the user's own fork.
  If a PR is needed to trigger CI, keep both its base and head in the fork.
- In a clone of a fork, `gh pr create` and `gh issue create` default to the
  parent repository. Pass `--repo <fork-owner>/<repo>` so the PR or issue
  lands in the fork.
- If the fork cannot run the CI, stop and ask the user how to proceed. This
  happens when Actions are disabled on the fork, when required secrets exist
  only upstream, or when jobs are gated on the upstream repository name.
  Do not fall back to an upstream PR.
