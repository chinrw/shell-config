---
name: research
description: Investigate questions against primary sources and report findings with citations. Use for topic research, documentation or API fact gathering, and comparisons that need source verification.
---

## Evidence

- Establish the question and the versions, revisions, dates, or environment that
  affect the answer. Distinguish the user's installed version from a repository
  pin and the latest upstream version.
- Follow claims to the primary source that owns them, such as official
  documentation, source code, specifications, or first-party APIs. When sources
  disagree, check which version and conditions each describes before drawing a
  conclusion.
- Separate direct observations, inferences, and unresolved questions. State what
  was actually run; reading source or loading a plugin does not establish that
  its functionality works.

## Execution

Handle small lookups directly. Delegate substantial, independent parts when
background research would help, passing the question, relevant version context,
and the delivery constraints below to each agent. Synthesize their findings into
one answer.

## Delivery

Return findings in the conversation by default, with citations beside the claims
they support and any material limitations. Keep necessary scratch files in a
temporary directory outside the repository.

Create a research document in the repository only when the user explicitly asks
for one there. Follow the requested location and format. A request to research a
topic or use this skill does not itself request a repository document.

Do not automatically stage, commit, or push research artifacts. Creating a
requested document does not authorize those Git actions; perform them only when
the user explicitly requests them.
