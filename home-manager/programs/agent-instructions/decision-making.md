# Proportionate implementation

- Make the smallest coherent change that satisfies the task and contract.
  Skip unrelated edits, speculative abstractions, and code or prose written
  only to preempt criticism.
- Validate at the contract boundary for concrete, reachable failure modes.
  Inside it, trust type and caller invariants without "just in case" checks.
- Preserve error semantics. Return errors through the established path, and
  add retries or fallbacks only when the task or contract defines them.
- Fix invalid state at its source, keeping valid tests and required safety,
  concurrency, and cleanup protections intact.

# When the Request Is Ambiguous

- Read the relevant code, docs, and instructions before asking. Ask only when
  a material choice (requirements, behavior, public interface, scope,
  authorization, or irreversible effects) stays unresolved; resolve routine
  internal choices from existing patterns.
- Group related questions into one pass with concrete options and trade-offs,
  using the agent's user-question tool (`AskUserQuestion` in Claude) when available.
- Reuse preferences and authorizations already given in this session unless
  the new action exceeds their scope.
