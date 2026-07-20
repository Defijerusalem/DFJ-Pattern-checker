# Finding Triage: Four Gates + Attack Vector Checklist

A structured pre-submission gate sequence for deciding whether a finding is real, reachable,
triggerable, and worth reporting — applied *before* severity grading, not after. Fail any gate →
reject or demote; later gates aren't worth evaluating for a finding that already failed an earlier
one. This formalizes discipline this engagement was already applying case-by-case (see cross-refs
below) into a repeatable checklist.

## Gate 1 — Refutation

Before trusting a finding, construct the strongest argument that it's wrong. Find the specific
guard, check, or constraint that would kill the attack — quote the exact line, trace how it blocks
the claimed step.

- **Concrete refutation** (a specific, named guard blocks the exact claimed step) → reject, or
  demote to a lead if a residual code smell is still worth tracking.
- **Speculative refutation only** ("probably wouldn't happen," "likely intended," no actual
  blocking mechanism found) → clears, continue to Gate 2.

*Cross-ref: this is the same exercise as the "imagine you're an adversarial triager" pass run
against the Origin ARM submission — the goal is to find the real objections before someone else
does, not to talk yourself out of a real finding.*

## Gate 2 — Reachability

Prove the vulnerable state can actually exist in a live/deployed system, not just in an idealized
reading of the code.

- **Structurally impossible** (an enforced invariant elsewhere in the code prevents the state from
  ever occurring) → reject.
- **Requires privileged action outside normal operation** (owner must misconfigure, a multisig
  must collude, a keeper must act outside its granted authority) → demote. This is the same
  boundary as Immunefi's standard "requires privileged access" exclusion.
- **Achievable through normal usage** — an ordinary admin action taken for legitimate reasons
  (adding a market, registering a new integration), common token behavior (fee-on-transfer,
  rebasing), or default configuration → clears, continue to Gate 3.

*Cross-ref: this is exactly the line Yearn's real triage drew on Y2 (rejected — required a keeper
acting outside normal authority) versus the Origin ARM finding (owner's `addMarkets()` call is
ordinary and well-intentioned; the actual exploit is performed by a second, fully unprivileged
party) — same gate, opposite outcomes, because the underlying facts differ. Getting this
distinction right before submitting is cheaper than getting it wrong after.*

## Gate 3 — Trigger

Prove an unprivileged (or minimally privileged) actor can execute the attack, profitably.

- **Only a trusted role can trigger it** → demote (report as medium/low, not critical).
- **Attack costs exceed extraction** (gas/capital cost of the attack is greater than what it
  yields) → reject.
- **Unprivileged actor can trigger it profitably** → clears, continue to Gate 4.

## Gate 4 — Impact

Prove material harm to an identifiable victim other than the attacker.

- **Self-harm only** (attacker can only lose their own funds; no other victim exists) → reject.
- **Dust-level, non-compounding, no cascade** → demote to low/informational.
- **Material loss to an identifiable victim** (user funds drained, protocol insolvency, data
  breach) → confirmed.

*Cross-ref: this is exactly why the 1inch `FarmingPool.deposit()` reentrancy finding was retracted
after the PoC was actually built — the completing `transferFrom`'s own debit recycled whatever the
reentrant `withdraw()` extracted, so an attacker with no prior capital netted zero. Looked like a
real Critical from code reading alone; failed Gate 4 the moment it was executed. Build the PoC
before trusting a severity grade — this gate is where that discipline pays off.*

## Severity adjustment after all four gates clear

- Attack requires a specific timing window (e.g., must land within one block) → −1 severity level.
- Attack requires non-trivial capital (e.g., a large flash loan against a low-value target) →
  −1 severity level.
- Impact is bounded (attacker can profit but cannot drain the full pool) → −1 severity level.
- A fix is already deployed on mainnet but not present in the reviewed commit → demote, note the
  discrepancy explicitly rather than silently dropping the finding.

## Promote before finalizing a findings list

- **Cross-contract echo**: same root cause confirmed in Contract A → check Contract B for the
  identical pattern before assuming it's isolated.
- **Partial-path completion**: the only weakness in a finding is an incomplete trace, but the path
  is reachable and unguarded → worth finishing the trace, not dropping the lead.
- **Cross-feature chaining**: a confirmed bug in one function enables a second, otherwise-minor
  issue elsewhere → chain them into one finding rather than reporting both separately.

## Do not report

- Linter warnings, compiler suggestions, gas micro-optimizations.
- Missing NatSpec or event emissions.
- Centralization risk with no concrete exploit path.
- Admin privileges functioning exactly as designed (unless the design itself is the vulnerability
  being reported).
- Preconditions that require the protocol to already be compromised by something else first.
- Rate limiting or a guard that genuinely prevents exploitation under the protocol's own stated
  threat model.

---

# Smart Contract Attack Vector Checklist

A fast pattern-matching pass across chains — not exhaustive, meant to be run early against any new
target before deeper manual review.

## EVM / Solidity
- Reentrancy: single-function, cross-function, cross-contract, read-only
- Integer overflow/underflow (pre-0.8.0, or `unchecked` blocks)
- Signature replay: missing chainId, nonce, or deadline
- `ecrecover` returning the zero address on malformed input, unchecked
- Oracle manipulation: spot price read, short TWAP window, stale Chainlink feed
- Flash loan: single-transaction price manipulation, governance vote manipulation
- First-depositor share-price inflation attack
- Front-running: DEX swap ordering, liquidation racing, NFT mint sniping
- Proxy storage collision, uninitialized implementation contract, UUPS upgrade-guard bypass
- Access control: unprotected initializer, inconsistent modifier usage, `tx.origin` for auth
- Unchecked return values from low-level `call`/`delegatecall`
- Block timestamp dependence for anything security-relevant
- Denial of service: unbounded loop over user-controlled array, forced revert, block gas limit

## Move / Aptos
- Capability accidentally copied or dropped
- `borrow_global_mut` without an ownership check
- Object type confusion (attacker supplies an unexpected object type)
- `upgrade_policy` set too permissively
- Upgrade capability left publicly accessible
- CCTP-style: single-attester threshold, attester rotation race condition
- Missing zero-address guard on role-assignment functions
- Orphaned minter allowance surviving minter removal
- Generic type parameter not constrained to the expected coin/asset type

## Solana / Anchor
- Missing account owner check
- Missing signer check
- Missing `has_one` or account `constraint`
- PDA seed collision
- Unchecked CPI (cross-program invocation) target
- Token account owner not validated
- Non-canonical bump seed accepted

## TRON
- TRC20 `transferFrom` without an allowance check
- Integer overflow in `mulDiv`-style helpers (pre-0.8-equivalent patterns)
- `block.number` used as a timestamp substitute
- Stake 2.0 resource ceiling silently failing rather than reverting
- `eth_call` pending-block-tag fallthrough

## Cross-Chain / Bridges
- Message replay across domains
- Missing destination-domain validation
- Attester/relayer single point of failure
- Replace-before-revoke gap window
- Bridge message race condition

*See `bridge.md` in this repo for the fully worked-out, case-validated version of the bridge
category — this checklist entry is a fast reminder, not a replacement for that file.*
