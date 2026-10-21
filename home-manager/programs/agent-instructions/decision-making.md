# Proportionate implementation

- Make the smallest coherent change that fully satisfies the task and
  established contract. Reuse existing mechanisms; avoid unrelated edits
  and speculative abstractions, configuration, or compatibility paths.
- Add guards for concrete, reachable failure modes or explicit contract
  and safety requirements. The failure need not have happened before,
  but "just in case" is not enough.
- Validate at the boundary responsible for enforcing the contract.
  Inside it, rely on invariants established by types or verified callers
  while those guarantees remain valid. Repeat checks only when a new
  boundary or state change can invalidate them.
- Preserve error meaning. Use the established error path instead of
  success-shaped defaults. Add retries or fallbacks only when the task
  or existing contract defines their recovery semantics.
- Fix invalid state at its source rather than masking it downstream.
  Do not introduce panics or weaken valid tests merely to simplify code.
- Preserve required security, concurrency, cleanup, and data-integrity
  protections. Remove existing guards only when their redundancy is
  established.

# When the Request Is Ambiguous

- Read the relevant code, documentation, and instructions before asking.
  Ask before implementing when they leave a material choice unresolved
  about requirements, observable behavior, public interfaces, scope,
  authorization, or irreversible effects.
- Resolve routine internal naming, file layout, and implementation choices
  using existing patterns and judgment within the agreed scope.
- Offer concrete options with trade-offs when useful, and group related
  questions so they can be answered in one pass.
- Follow preferences and authorizations already given in this session
  without re-asking. Ask again only if the proposed action exceeds their
  scope.
