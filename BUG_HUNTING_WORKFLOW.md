---
name: bug-hunting-workflow
description: >
  A four-stage workflow for finding NOVEL bugs in smart contract code (as opposed to
  dfj-pattern-checker's job, which is matching against a fixed library of already-known
  exploit patterns). Stages: Detect, Reason, Exploit, Validate. Use this when someone
  shares a contract and asks for a real security review / bug hunt, not a pattern-library
  check against known historical incidents.
---

# Bug Hunting Workflow: Detect → Reason → Exploit → Validate

## Why this is a separate workflow from dfj-pattern-checker

`SKILL.md` (dfj-pattern-checker) is explicit that it does NOT find novel bugs — it matches
code against a library of patterns already validated by real, dated incidents elsewhere.
That's the right tool when the question is "does this protocol have a known failure mode."

This workflow answers a different question: "is there a bug in THIS specific code that
nobody has documented anywhere, because it's unique to this contract's own logic." It is
slower, requires actually reading and reasoning about the code rather than matching against
a checklist, and produces fewer, higher-confidence findings rather than a broad scan.

Run dfj-pattern-checker first if a known-pattern scan hasn't been done — it's cheap and
catches the well-known stuff immediately. Run this workflow for the harder, protocol-specific
questions a fixed pattern library can't answer.

## Stage 1 — Detect

Goal: generate candidate findings, not conclusions. Over-generate here; the later stages
filter out noise.

Read every state-changing function and ask, for each one:

- **Access control.** Who can call this? Does an external modifier (`onlyRole`, `onlyOwner`)
  match what the function's own doc comment / internal logic claims should be allowed? A
  mismatch between the modifier and an internal fallback check is a classic bug — the
  modifier reverts before the internal check is ever reached, silently making documented
  "or admin" fallback logic dead code.
- **Live vs. stale authorization.** Does a check compare `msg.sender` to a stored address
  (`msg.sender == cert.issuer`), or does it re-verify the address still holds the role right
  now (`hasRole(ROLE, msg.sender)`)? A revoked/rotated privileged address that still passes a
  stale address-equality check is a real bug, not a hypothetical one.
- **"Who" vs. "whether."** Any time a stored value's mere *existence* (a registered
  beneficiary, an approved address, a flag) is used to skip an independent confirmation step,
  ask: does that stored value actually prove the triggering event happened, or does it only
  answer "who would receive it if it did"? Confusing the two is the single highest-value
  pattern this workflow exists to catch — a privileged actor can often manufacture the "who"
  state themselves and use it to bypass a check that was supposed to gate the "whether."
- **TOCTOU / staged operations.** Anywhere a sensitive action is proposed now and executed
  later (a pending-request pattern, a timelock, a two-step confirm), ask what happens if the
  state being checked at *execution* time has changed since *proposal* time. Does execution
  re-validate against current state, or trust a snapshot taken at proposal time?
- **Overwrite without cancellation.** Can a second call silently replace a first call's
  pending/staged state before it resolves, with no explicit cancel and no distinct event?
  This erases the audit trail an approver was relying on.
- **Reentrancy.** Trace every external call (`_safeMint`, ERC-777 hooks, low-level `call`)
  and confirm all sensitive state is written before the call, not after.
- **Signature/`staticcall` verification.** For any ERC-1271-style check, is both the `success`
  boolean AND the returned magic value checked? A reverting `staticcall` returns revert data
  as ordinary return data — checking only the bytes is a real bug class (see `SKILL.md` 5b).
- **Storage hygiene / dangling references.** When an object transitions out of an active
  state (burned, revoked, superseded), is every other mapping that pointed at it also
  cleared? A stale pointer that's merely inert today can become live again after a future
  change elsewhere in the code.
- **Function signature drift.** When a function is meant to override a parent/interface
  method, confirm the signature matches EXACTLY. A near-miss silently creates a new, dead
  function instead of an override — no compiler error, no revert, just code that never runs.
- **Unbounded input.** Any user/privileged-supplied string or array with no length cap —
  distinguish gas-griefing-only (self-funded, low severity) from anything that could bloat
  a shared resource other parties pay for.

Write down every candidate, even weak ones, with a one-line description and the exact
file/function/line. Don't filter yet — that's Stage 2 and 3's job.

## Stage 2 — Reason

Goal: for each Stage-1 candidate, articulate the actual invariant being broken, in one or
two sentences, and check whether anything else in the code already defends against it.

- State the invariant precisely: "X should only be possible if Y is true" — then show the
  exact code path where X happens without Y actually being checked.
- Actively look for the counter-argument. Is there a modifier earlier in the call chain, a
  check in a different function that's always called first, or a design note explaining why
  this is intentional? If a plausible defense exists, go find it in the code before
  concluding it's a bug — don't stop at the first symptom.
- If the "bug" turns out to be intentional/documented behavior, or already defended
  elsewhere, drop it. This step is where most Stage-1 candidates die — that's expected and
  correct, not a failure of Stage 1.
- Distinguish root cause from symptom. If two candidates from Stage 1 turn out to be two
  faces of the same underlying flaw (e.g., a bypassable authorization combined with a
  confirmation step that trusts that same bypassable state), name the actual root cause once
  rather than reporting it as two separate findings.

Anything that survives this stage with a precisely-stated, undefended invariant violation
moves to Stage 3.

## Stage 3 — Exploit

Goal: prove reachability and real-world impact, not just theoretical possibility.

- **Construct the concrete call sequence.** Name the actor (which role, which starting
  state), the exact function calls in order, and the resulting state change. If you can't
  write this sequence out concretely, the finding isn't ready — go back to Stage 2.
- **Check the economics.** Does exploiting this cost the attacker something disproportionate
  to the gain (gas cost, calldata cost, a bond that gets slashed)? A privileged-role-gated
  action whose only "damage" is the privileged actor's own wasted gas is a different severity
  tier than an unprivileged-facing theft path — say so explicitly, don't inflate severity.
  Recall the storage-cost/calldata-cost gas ceiling reasoning: it naturally bounds how far
  some "unbounded input" issues can actually go before the transaction becomes uneconomical.
- **Check for duplication.** Before treating this as a fresh finding, check it against any
  known-issues list, prior audit report, or public disclosure for this exact
  contract/protocol. A finding that duplicates an already-acknowledged issue is not a new
  bug — this has caused real wasted submissions before (an SSV finding in this project's own
  history turned out to duplicate an already-known Immunefi Known Issue). Check first.
- **State the actual impact**, not the maximum theoretical impact: whose funds/permissions/
  state change, how much, and under what precondition. "An issuer can steal any certificate
  they themselves issued" is a precise, checkable impact statement; "this could be bad" is
  not.

## Stage 4 — Validate

Goal: confirm the finding is real against the ACTUAL current, live/deployed state — not a
static local checkout, not an assumption from reading alone — and confirm any proposed fix
actually works.

- **Verify against live state, not a stale snapshot.** A local git clone can be weeks behind
  `origin/master`. Before reporting a finding as fresh, `git fetch` the actual branch, check
  `git log`/`git show` for whether this exact code path was already changed, and diff the
  local working tree against the remote tip. This project's own history has multiple cases
  where a finding looked fresh in a stale local checkout but was already fixed (or was an
  intentionally shipped feature) in the actual deployed/current code — always check before
  reporting.
- **Re-trace fresh, independently of the reasoning that found it.** Don't just re-read your
  own Stage 2 argument and nod — walk the exploit sequence again from a blank slate, as if
  checking someone else's claim, and confirm every step still holds.
- **Runtime-verify any proposed fix — compiling is necessary, never sufficient.** A fix that
  compiles cleanly can still be wrong: a classic case is reading a storage struct's fields
  *after* `delete`-ing that same slot — the code compiles fine, but every field read back is
  zeroed, because a Solidity storage reference aliases the live slot rather than snapshotting
  it at assignment time. This project's own eval history has a documented case of exactly this:
  one run compile-checked a fix and called it verified, while a separate run on the same file
  caught the actual bug by reasoning about execution order, not syntax. Set up an isolated
  build (pin the exact dependency versions the target project uses), then go further than
  compiling: write and run an actual test (Foundry/Hardhat/whatever the target project uses)
  that (a) reproduces the Stage 3 exploit sequence against the ORIGINAL code and confirms it
  succeeds, then (b) re-runs that same sequence against the FIXED code and confirms it's now
  blocked, and (c) runs a control case confirming the legitimate/intended fast path still works
  unchanged. "It compiles" answers "is this syntactically valid Solidity," not "does this
  actually do what I claimed" — only executing it answers the second question.
- **When live execution genuinely isn't available**, say so explicitly rather than letting a
  compile-only check read as if it were runtime-verified — e.g. "compiled clean; not executed
  against a live EVM in this session" is an honest, weaker claim than presenting a compile pass
  as validation of behavior.
- **Calibrate severity honestly, in both directions.** State plainly whether this is a
  genuine unprivileged-facing loss vector or a privileged-actor/self-harm-only issue, whether
  it needs a multi-party collusion or a single compromised key, and what blast radius it
  actually has. Don't equally-alarm a cosmetic/gas issue and a fund-theft path.
- **Deliver the fix, not just the description**, when the user wants code: full corrected
  file or precise diff, with an inline note at each change explaining what was wrong and why
  the fix closes it — not just prose describing the change separately from the code.

## Output shape

For each surviving finding, present:

1. **Title** — one line naming the mechanism, not just "bug in function X."
2. **Invariant violated** — the Stage 2 statement.
3. **Exploit sequence** — the Stage 3 concrete call sequence, actor, and impact.
4. **Severity** — calibrated per Stage 4, with the reasoning shown, not just a label.
5. **Fix** — the corrected code, compile-verified, with inline notes.
6. **Duplication check result** — what you checked it against and what you found (or "no
   known-issues list was available to check against").

Never present a finding as final without having gone through Stage 4 in full — a plausible
Stage 2/3 argument that hasn't been checked against live/current state and compiled is a
draft, not a finished finding.
