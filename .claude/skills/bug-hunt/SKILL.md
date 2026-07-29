---
name: bug-hunt
description: >
  Finds NOVEL, protocol-specific bugs in smart contract code by actually reading and
  reasoning about the logic — access-control mismatches, stale-vs-live authorization checks,
  TOCTOU gaps in staged/pending operations, "who vs. whether" confused-deputy bugs,
  reentrancy, signature-verification gaps, dangling storage, function-signature drift,
  unbounded input, unit/basis mismatches across contract boundaries (assets vs. shares,
  price before vs. after fee), dual entrypoints into a flow the docs claim is single-path,
  pause that stops users but not the accounting path, multiple minters sharing one supply
  cap, stale price/state reads, and upgrade storage-layout drift against the live proxy. This
  is the opposite tool from dfj-pattern-checker (which only matches against a fixed library
  of already-known historical incidents and explicitly does NOT find new bugs) — use
  bug-hunt whenever someone shares a specific contract/codebase and wants a real security
  review, asks to "find bugs," "audit this," "check for vulnerabilities," wants a
  bug-bounty-style writeup, or asks you to fix issues in their own contract. Trigger this
  even if they don't say "novel" or "bug-hunt" explicitly — any request to review a specific
  piece of code for security issues (as opposed to checking a named protocol against known
  past incidents) belongs here. Follows a four-stage methodology: Detect, Reason, Exploit,
  Validate.
---

# Bug Hunt: Detect → Reason → Exploit → Validate

## Why this is a different tool from dfj-pattern-checker

`dfj-pattern-checker` (this repo's root `SKILL.md`) is explicit that it does NOT find novel
bugs — it matches code against a library of patterns already validated by real, dated
incidents elsewhere. That's the right tool for "does this named protocol have a known
failure mode."

This skill answers a different question: "is there a bug in THIS specific code that nobody
has documented anywhere, because it's unique to this contract's own logic." It's slower,
requires actually reading and reasoning about the code rather than matching a checklist, and
produces fewer, higher-confidence findings rather than a broad scan.

If a known-pattern scan hasn't been done yet, running `dfj-pattern-checker` first is cheap
and catches the well-known stuff immediately. Use this skill for the harder,
protocol-specific questions a fixed pattern library can't answer — including reviewing a
contract nobody else has ever looked at, like a user's own unreleased code.

The full standalone version of this methodology also lives at the repo root as
`BUG_HUNTING_WORKFLOW.md`, for reading outside of an active Claude session — this file and
that one should stay in sync if either is edited.

## Stage 1 — Detect

Goal: generate candidate findings, not conclusions. Over-generate here; the later stages
filter out noise.

**Before diving into any single function, ask the boring question first: what does contract
A assume contract B is still doing?** The unique bugs are rarely in the scary-looking
function — they're in the assumptions between modules, where one piece of code still
believes another means something it no longer means (or never quite meant). Every bullet
below is a specific, checkable instance of that one question. Treat this as the lens you
look through, not just one more item to tick off.

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
  pattern this skill exists to catch — a privileged actor can often manufacture the "who"
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
- **Signature/`staticcall` verification.** For any ERC-1271-style check, is both the
  `success` boolean AND the returned magic value checked? A reverting `staticcall` returns
  revert data as ordinary return data — checking only the bytes is a real bug class.
- **Storage hygiene / dangling references.** When an object transitions out of an active
  state (burned, revoked, superseded), is every other mapping that pointed at it also
  cleared? A stale pointer that's merely inert today can become live again after a future
  change elsewhere in the code.
- **Function signature drift.** When a function is meant to override a parent/interface
  method, confirm the signature matches EXACTLY. A near-miss silently creates a new, dead
  function instead of an override — no compiler error, no revert, just code that never runs.
- **Unbounded input.** Any user/privileged-supplied string or array with no length cap —
  distinguish gas-griefing-only (self-funded, low severity) from anything that could bloat a
  shared resource other parties pay for.
- **Units and basis, every time a value crosses a boundary.** Write down what unit an amount
  is actually in at each hop: assets vs. shares, price before fee vs. after fee, a raw
  reported balance vs. the balance after the contract strips something out of it. If two
  places use different bases for what's nominally "the same" value, that's phantom PnL, a
  weird floor, or quiet dilution — and it's exactly the kind of thing automated tools barely
  catch, because both sides type-check fine on their own.
- **Dual paths where the docs claim one mandatory route.** If the documentation or a comment
  says "all settlement must go through the controller" (or any equivalent single-mandatory-
  path claim), go find every OTHER way to open or finish that same flow: a legacy path, a bot-
  only path, an owner-only shortcut, a direct call straight to the leaf contract that skips the
  intermediary entirely. Designs lie exactly here — the doc describes the intended path, not
  every path the code actually allows.
- **What pause actually stops.** Don't just confirm a pause flag exists and blocks the obvious
  user-facing functions — trace whether it also blocks the accounting/settlement path, or only
  the deposit/withdraw entrypoints. A pause that freezes users but leaves internal share-price
  accrual, fee accrual, or liquidation math still running is worse than no pause at all, because
  it looks safe without being safe.
- **Every minter/every path that increases the same balance, and where the cap actually lives.**
  When more than one contract or function can mint the same asset (or increase the same
  counter), map all of them and ask: is the cap enforced on total supply, on a local per-path
  counter, or only inside one specific entrypoint? A cap correctly enforced on the "main" mint
  function while a second, less-obvious path keeps minting into the same system is a real,
  recurring bug class — and it's easy to miss if the review only reads the function that looks
  like the mint function.
- **Stale price / stale state.** Any time a payout, valuation, or liquidation decision reads a
  `lastSettled`/`lastSample`/`lastRound`-style value, check whether freshness is actually
  enforced before that value is used, and whether pause (or any fast path) skips that freshness
  check the slow path has. A lot of "instant"/fast-path features are just the slow path with
  the safety rails quietly removed.
- **Upgrade storage layout vs. the live proxy.** Don't just read the new implementation in
  isolation — pull the storage layout the deployed proxy actually has right now and diff it
  against what the new code expects slot-by-slot. Reordering variables in the source file moves
  what a mapping's root slot resolves to even though nothing in the diff looks alarming; this
  can fully brick core flows via a completely ordinary, non-malicious upgrade — no external
  attacker required, the owner just runs the migration script and the protocol breaks. That
  still counts as a finding.

Write down every candidate, even weak ones, with a one-line description and the exact
file/function/line. Don't filter yet — that's Stage 2 and 3's job.

## Stage 2 — Reason

Goal: for each Stage-1 candidate, articulate the actual invariant being broken, in one or two
sentences, and check whether anything else in the code already defends against it.

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
- **Never take a reassuring comment at face value — reproduce it.** "Small undercharge is
  intentional," "conservative by design," "dust only, ignore it": these are design claims, not
  proof. Reproduce the actual behavior the comment describes, then ask the question the
  comment doesn't answer — does it stay dust under a longer sequence of ordinary activity, not
  just a single call? Sometimes it genuinely stays dust. Sometimes it compounds until it flips
  a gate, zeroes a payout path, or never catches up because a clock kept advancing underneath
  it. If the real outcome is bigger than what the comment claims, that gap between claimed and
  actual behavior is the finding — write down both the comment's claim and what you actually
  reproduced.

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
  Storage-cost/calldata-cost gas economics naturally bound how far some "unbounded input"
  issues can actually go before the transaction becomes uneconomical — factor that in rather
  than assuming unbounded means unlimited real-world impact.
- **Check for duplication.** Before treating this as a fresh finding, check it against any
  known-issues list, prior audit report, or public disclosure for this exact
  contract/protocol (e.g. an Immunefi "Known Issues" page, a listed audit's findings). A
  finding that duplicates an already-acknowledged issue is not a new bug — submitting one
  anyway wastes a real bounty submission. Check first.
- **State the actual impact**, not the maximum theoretical impact: whose funds/permissions/
  state change, how much, and under what precondition. "An issuer can steal any certificate
  they themselves issued" is a precise, checkable impact statement; "this could be bad" is
  not.
- **Attack the trust assumption itself, not just the access-control check.** Don't stop at
  confirming "only owner can call this" — ask what happens when the privileged role is wrong,
  rushed, or just careless, not only when it's actively malicious. Can they crank a fee high
  enough that users get almost nothing back? Change a rate mid-flight in a way that strands
  in-progress positions? Pull an emergency balance people still depend on? Upgrade into a
  broken layout? Swap a dependency and wipe state the product relies on? "Trust the multisig"
  is not a fix — missing bounds, a missing timelock, and a blast radius nobody sized are still
  findings, even with zero external attacker in the story. A lot of the unique medium/low
  findings that separate a good report from a decent one are exactly this: nobody modeled the
  trusted role as clumsy, only as hostile or as perfectly careful.

## Stage 4 — Validate

Goal: confirm the finding is real against the ACTUAL current, live/deployed state — not a
static local checkout, not an assumption from reading alone — and confirm any proposed fix
actually works.

- **Verify against live state, not a stale snapshot.** A local git clone can be weeks behind
  `origin/master`. Before reporting a finding as fresh, `git fetch` the actual branch, check
  `git log`/`git show` for whether this exact code path was already changed, and diff the
  local working tree against the remote tip. A finding that looks fresh in a stale local
  checkout can turn out to already be fixed, or an intentionally shipped feature, in the
  actual current code — always check before reporting.
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
- **Check the PoC's wiring against production wiring.** Before finalizing severity, rerun the
  failing case with whatever config production actually sets — the real deploy parameters, not
  whatever a scary, maximally-adversarial fixture happened to configure. If the exploit only
  works because the test setup left something unwired that mainnet always wires up, severity
  usually drops (say so). If it still breaks under the honest, real-config path, that's the
  stronger writeup — unique findings more often come from normal operations under real
  configuration than from the most evil fixture you can invent.
- **Deliver the fix, not just the description**, when the user wants code: full corrected
  file or precise diff, with an inline note at each change explaining what was wrong and why
  the fix closes it — not just prose describing the change separately from the code.

## Quick reference: the boring questions worth asking every time

Nothing fancy here, just consistency. Before calling a review done, confirm each of these was
actually asked, not just the functions that looked scary:

- Unit/basis notes written down at every point a value crosses a contract boundary
- Every entrypoint for each critical phase, not just the one the docs call "the" entrypoint
- What pause really stops — accounting path included, not just user-facing functions
- Upgrade storage layout diffed against the live proxy, not just the new source read in isolation
- Deploy config vs. test setup — does the PoC still break under production wiring
- Every minter / every path that increases the same balance, and where the cap actually lives
- Reassuring "dust"/"intentional"/"conservative" comments, reproduced under a longer sequence
- The privileged path, modeled as clumsy and rushed, not just as hostile or as perfectly careful

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

If the user is doing a quick, low-stakes read of their own small contract rather than a
formal audit/bug-bounty submission, it's fine to compress stages 1-3 into a single pass and
move straight to writing the fix — but Stage 4's compile-check and live-state verification
still apply before calling anything done.
