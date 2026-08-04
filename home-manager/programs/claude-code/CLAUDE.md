# User-scope Claude Configuration

Rules shared with Codex and opencode are appended below from
`home-manager/programs/agent-instructions/`. Only Claude-specific rules
belong in this section.

## Questionnaires

- Use the `AskUserQuestion` tool to present the options described under
  "When the Request Is Ambiguous".

## Claude and Codex delegation

Claude plans, decides, reviews, and validates; Codex writes the
implementation.

Delegate by invoking the codex-implementation skill (it defines the full
handoff, review, and validation workflow) when:

- the change spans multiple files;
- the implementation exceeds a small localized edit;
- the task includes substantial test creation;
- debugging requires independent investigation;
- repetitive refactoring can be cleanly isolated;
- a second implementation would improve confidence.

Claude may directly handle: small localized edits, configuration changes,
documentation changes, obvious bug fixes, and tasks where delegation overhead
exceeds implementation effort.
