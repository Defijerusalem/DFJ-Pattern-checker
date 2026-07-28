# Security Review — `LandCertificate.sol` (Onílẹ̀ land certificate NFT)

I ran this through the `bug-hunt` skill's four-stage methodology (Detect → Reason → Exploit →
Validate) rather than a pattern-matching pass. Two findings are serious enough that I didn't
stop at "this looks wrong" — I wrote Foundry tests that actually execute the exploit sequences
against your real compiled bytecode, and then wrote and compile/test-verified fixes for all
three material findings. Details on that below; here's the headline first.

**Bottom line:** the contract's soulbound/transfer-lockdown logic, sale-approval flow, and
storage hygiene are solid. But there's one critical bug that lets a single `ISSUER_ROLE` holder
(the entity your own doc comments explicitly call a possible threat — "a legitimate one whose
signers have gone rogue") completely bypass the admin-confirmation safeguard you built
specifically to stop that, and seize any certificate they issued under the "inheritance" reason
code. There's also a second, independent bug that quietly breaks your admin's emergency-fallback
powers across four functions. Both are fixed below, with the fixes compiled and re-tested against
the exploit to confirm they actually close the hole without breaking the legitimate fast paths.

---

## Validation methodology (what I actually did, not just read)

- Compiled `LandCertificate.sol` as-is with `solc 0.8.24`, `--via-ir`, against OpenZeppelin
  Contracts v5.1.0 — exactly the toolchain your own top-of-file deployment note specifies.
  **Compiles clean, zero errors/warnings.**
- Set up a Foundry project (forge-std + the same OZ v5.1.0) and wrote executable exploit tests
  for every finding below, run against a deployed instance of your actual contract on a local
  EVM — not just a code-reading argument.
- Wrote a patched copy of the contract with concrete fixes for the three material findings,
  compile-checked it, then re-ran the same exploit tests against the patch: all three exploits
  are blocked, and a control test confirms the legitimate/intended fast paths still work
  unchanged (no regression).
- This is a fresh, unreleased contract with no public audit history or bug-bounty "known issues"
  page I could check findings against — I have no reason to believe any of this is already
  known/accepted, but flagging that explicitly per the methodology's duplication-check step.

---

## Finding #1 — CRITICAL: Issuer can self-manufacture the "beneficiary" fact that's supposed to require independent admin sign-off

**Title:** `reassignBeneficiary()` + `reissue(..., INHERITANCE)` lets the certificate's own
issuer bypass the admin-confirmation safeguard entirely.

**Invariant violated:** Your own design intent, stated directly in the code comments: for
INHERITANCE reissues with no beneficiary independently registered by the actual owner, "a
separate `confirmReissue()` from the admin multisig alone" is required, specifically so "the
certificate's own issuer can no longer move it through those two paths unilaterally." That
invariant is not enforced — the issuer can unilaterally satisfy it themselves.

**Root cause:** `reissue()` decides whether admin confirmation is needed by checking only
*whether* `beneficiaryOf[oldTokenId]` is non-zero and matches `to` — not *who* set it or
*whether that value reflects the actual owner's independent choice*. But `reassignBeneficiary()`
— callable by the certificate's own issuer, with **no** requirement that a beneficiary was
previously set, and **no** requirement that the real owner be unreachable/deceased — lets that
same issuer set `beneficiaryOf[tokenId]` to any address, including their own accomplice, seconds
before calling `reissue()`. This is exactly the "who vs. whether" confused-deputy pattern: the
stored value only tells you *who would receive it if inheritance were legitimate*, not *whether*
it actually happened independent of the issuer — and the issuer can manufacture the "who" to
skip the "whether" check.

**Exploit sequence (proven, not hypothetical — see `test_IssuerBypassesAdminConfirmationViaBeneficiaryReassignment`):**
1. Issuer (holding `ISSUER_ROLE`, the certificate's issuer of record) issues a certificate to
   `realOwner`. `realOwner` never calls `registerBeneficiary()` — completely normal, most owners
   won't have done this yet.
2. Issuer calls `reassignBeneficiary(tokenId, attacker)`. This succeeds — the only gate is
   `msg.sender == cert.issuer`, which the issuer trivially satisfies for their own certificate.
3. Issuer immediately calls `reissue(tokenId, attacker, ..., ReasonCode.INHERITANCE)`.
   `beneficiaryOf[tokenId] == attacker` and `to == attacker`, so no `BeneficiaryMismatch` revert;
   `beneficiary != address(0)`, so `requiresAdminConfirmation` is **false**. The reissue executes
   **immediately** in the same transaction sequence — `realOwner`'s certificate is burned and a
   new one minted straight to `attacker`. No `confirmReissue()`, no `DEFAULT_ADMIN_ROLE` signer,
   ever involved.
4. This works even if `realOwner` is alive, reachable, and never consented to anything — nothing
   on-chain requires the owner to be dead or unreachable for "inheritance." It also works even if
   the owner **did** previously register a real family member as beneficiary: step 2 simply
   overwrites that too, since `reassignBeneficiary` has no restriction limiting it to correcting
   a stale/previously-nonzero value.

I ran this exact sequence against your compiled contract in Foundry; it passes, confirming the
theft executes with zero admin involvement at any point.

**Severity: Critical.** This is not a self-harm/gas-only issue — it's an unprivileged-facing loss
vector for the certificate's actual owner, triggerable unilaterally by a single privileged actor
(one issuer's compromised or dishonest signers), which is precisely the threat model your own
comments say the admin-confirmation step exists to defend against. It nullifies that defense for
every single INHERITANCE reissue, not just the "no independent anchor" edge case the code
comments call out — an issuer can override even a real, owner-set beneficiary first. `SALE`
reissues remain safe (gated by the owner's own `approveSale()`); `LOST_WALLET` remains safe (its
`requiresAdminConfirmation` is unconditional). Only `INHERITANCE` is affected, but that's still
one of the two paths your entire staged-confirmation design exists for.

**Fix (compiled + exploit-retested — confirmed closed with no regression):** Track *who* set the
current beneficiary value, and only let an **owner-attested** value skip admin confirmation.

```solidity
// New storage: distinguishes an owner's own attestation from an issuer/admin override.
mapping(uint256 => bool) private _beneficiarySetByOwner;

function registerBeneficiary(uint256 tokenId, address beneficiary) external {
    if (ownerOf(tokenId) != msg.sender) revert NotCertificateOwner();
    beneficiaryOf[tokenId] = beneficiary;
    _beneficiarySetByOwner[tokenId] = true;              // <-- owner-attested
    emit BeneficiaryRegistered(tokenId, beneficiary);
}

function reassignBeneficiary(uint256 tokenId, address beneficiary) external {
    Certificate storage cert = certificates[tokenId];
    if (cert.status != Status.Active) revert CertificateNotActive();
    if (msg.sender != cert.issuer && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
        revert NotAuthorizedForCertificate();
    }
    beneficiaryOf[tokenId] = beneficiary;
    _beneficiarySetByOwner[tokenId] = false;              // <-- NOT owner-attested, override only
    emit BeneficiaryReassigned(tokenId, beneficiary, msg.sender);
}

// inside reissue():
address beneficiary = beneficiaryOf[oldTokenId];
bool ownerAttestedBeneficiary = beneficiary != address(0) && _beneficiarySetByOwner[oldTokenId];
if (reason == ReasonCode.INHERITANCE && beneficiary != address(0) && to != beneficiary) {
    revert BeneficiaryMismatch();
}
...
bool requiresAdminConfirmation =
    reason == ReasonCode.LOST_WALLET || (reason == ReasonCode.INHERITANCE && !ownerAttestedBeneficiary);
```

With this fix: `reassignBeneficiary` still works exactly as documented (issuer/admin can correct
a stale registration) — but doing so no longer counts as an independent attestation, so
`reissue(INHERITANCE)` built on a reassigned value still stages for admin confirmation, same as
a never-set beneficiary. A beneficiary the real owner set themselves still fast-paths with no
change in behavior. I confirmed both properties by re-running the exploit test (now blocked,
result: staged not executed, `realOwner` retains the certificate) and a second test confirming
the legitimate owner-attested fast path still executes immediately with no regression.

**Duplication check:** No known-issues list or prior audit exists for this contract to check
against (it's unreleased, per the review request). Not a duplicate of anything I could find.

---

## Finding #2 — MEDIUM: Documented admin fallback on four functions is unreachable dead code

**Title:** `onlyRole(ISSUER_ROLE)` gates `issue()`, `reissue()`, `revoke()`, and
`registerPlots()` at the modifier level, silently making their internal "or admin" fallback
checks unreachable.

**Invariant violated:** Doc comments state, verbatim: `revoke()` — "Callable only by the
certificate's own issuer of record **(or the admin multisig)**." `reissue()`/`_executeReissue()`
similarly describe admin as a fallback caller. `registerPlots()`: "only the issuer... **(or
admin)** can re-register it." The code's *internal* logic matches this
(`if (msg.sender != X && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert`) — but none of that
internal logic is ever reached for a pure `DEFAULT_ADMIN_ROLE` holder, because the function's
*external* modifier is `onlyRole(ISSUER_ROLE)`, which reverts before the function body — and
therefore before the internal admin-fallback check — ever executes.

**Exploit/reproduction (proven — see `AdminFallbackDead.t.sol`, 5/5 tests pass):** Deployed the
contract with an `admin` holding only `DEFAULT_ADMIN_ROLE` (never separately granted
`ISSUER_ROLE` — the natural, undocumented-as-required starting state). Confirmed `admin` cannot
call `revoke()`, `reissue()`, `issue()`, or `registerPlots()` — each reverts with
`AccessControlUnauthorizedAccount(admin, ISSUER_ROLE)`, i.e. rejected for lacking `ISSUER_ROLE`,
never even reaching the internal "or admin" branch. A fifth test confirms the *only* way to make
the documented fallback actually work is an undocumented extra step: the admin must first
`grantRole(ISSUER_ROLE, adminAddress)` to itself — at which point the internal logic (which was
never actually dead in principle, just unreachable via this external gate) does work correctly.

**Severity: Medium.** This is not a fund-loss vector — it's a broken safety net. The scenarios
these fallbacks exist for (an issuer's multisig compromised, dissolved, or simply unresponsive,
and admin needing to step in on plot registration, issuance, reissue, or revocation) are
precisely the moments this silently fails, unless whoever operates the admin key already knows
to pre-emptively self-grant `ISSUER_ROLE` — which nothing in the contract or its comments tells
them to do. Low likelihood of being noticed until the emergency where it's needed; worth fixing
before launch rather than discovering during an actual incident.

**Fix (compiled + exploit-retested):**

```solidity
error NotIssuerOrAdmin();

modifier onlyIssuerOrAdmin() {
    if (!hasRole(ISSUER_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
        revert NotIssuerOrAdmin();
    }
    _;
}
```
Replace `onlyRole(ISSUER_ROLE)` with `onlyIssuerOrAdmin` on `issue()`, `registerPlots()`,
`reissue()`, and `revoke()` only (leave `registerEstate()` and `setIssuerBranding()` as
`onlyRole(ISSUER_ROLE)` — those have no documented admin fallback and none is needed). The
existing internal per-record checks (`msg.sender == estate.issuer`, `msg.sender == cert.issuer`,
etc., "or admin") are untouched and continue to do the fine-grained authorization — this fix only
makes the admin branch of that logic *reachable*. Re-tested: admin can now call `revoke()`
without any prior self-grant, matching the doc comment exactly; issuer-only calls are unaffected.

**Duplication check:** Same as above — no known-issues source to check against.

---

## Finding #3 — LOW/MEDIUM: A pending reissue proposal can be silently swapped before admin confirms it

**Title:** `reissue()` overwrites an existing `PendingReissue` entry with no check and no
cancellation event, letting a second proposal replace the first with only a fresh
`ReissueProposed` log — nothing that reads as "this replaced something."

**Invariant violated:** An admin who has reviewed off-chain evidence for proposal A and is about
to call `confirmReissue()` should be confirming proposal A — not whatever is currently staged at
call time, which the issuer can change up to and including the block before the admin's
transaction lands.

**Exploit sequence (proven — see `PendingOverwrite.t.sol`):** Issuer proposes a `LOST_WALLET`
reissue of `tokenId` to `legitRecipient` (stages correctly, since `LOST_WALLET` always requires
confirmation). Before any `cancelReissueProposal()` call, the same issuer calls `reissue()` again
for the same `tokenId` with a different recipient, `swappedRecipient`. This silently overwrites
the pending entry — no revert, no distinct "replaced" signal, just a second `ReissueProposed`
event. When admin then calls `confirmReissue(tokenId)`, the certificate goes to
`swappedRecipient`, not the `legitRecipient` the admin may have reviewed evidence for.

**Severity: Low/Medium.** This requires the proposing issuer to act again before admin confirms
— either changing its mind (benign) or deliberately front-running the admin's confirmation
transaction with a swap (requires mempool visibility/timing, and still requires the same
privileged `ISSUER_ROLE`/issuer-of-record access Finding #1 discusses). It's a real gap, not a
theoretical one, but it depends on an admin process that doesn't re-verify on-chain state
immediately before confirming — a disciplined admin workflow (reading `pendingReissues` fresh
right before signing) mitigates it even unpatched. Still worth closing at the contract level
rather than relying on operational discipline.

**Fix (compiled + exploit-retested):**
```solidity
if (requiresAdminConfirmation) {
    if (pendingReissues[oldTokenId].exists) revert PendingReissueAlreadyExists();
    pendingReissues[oldTokenId] = PendingReissue({ ... });
    ...
}
```
Forces an explicit `cancelReissueProposal()` before a new one can be staged, restoring a clean,
auditable one-proposal-at-a-time invariant. Re-tested: a second `reissue()` call while one is
pending now reverts with `PendingReissueAlreadyExists`, confirmed via Foundry.

**Duplication check:** No known-issues source to check against.

---

## Lower-severity / informational observations (read and reasoned through, didn't rise to full findings)

- **Unbounded string length on `estateName` / `plotId` / `surveyPlanNumber` / `coordinates`.**
  Unlike `logoSvgPath` (capped at `MAX_LOGO_BYTES = 3000`), these have no length cap. Since
  `registerEstate`/`registerPlots`/`issue` are issuer-gated, the immediate storage cost is mostly
  self-funded gas-griefing (low real severity — the caller pays for their own bloat). The one
  place this could externalize cost is `_executeReissue()`, which copies these strings forward
  on every reissue and `confirmReissue()` (admin-paid gas) — so a rogue issuer registering an
  oversized string, then repeatedly forcing `LOST_WALLET` reissues, forces the *admin* to pay
  higher gas each time they confirm. Bounded by ordinary gas-cost economics (nobody's going to
  push this to megabytes), but worth a length cap for hygiene, mirroring what you already did for
  `logoSvgPath`.

- **`_requireSafeString()` blocks specific ASCII bytes only** (already disclosed in your own doc
  comment: multi-byte UTF-8 is untouched). Since issuer-supplied strings (estate name, plot ID)
  are rendered directly into the on-chain SVG/JSON, an issuer could in principle use Unicode
  homoglyphs or bidi-override characters for a cosmetic-spoofing effect (e.g. a plot ID that
  visually resembles a different one). Low severity, issuer-privileged, and you've already
  flagged this exact tradeoff explicitly in comments — noting only for completeness, no action
  needed unless you want to go further than your stated scope.

- **Dangling `PendingReissue` entries survive `revoke()`.** `revoke()` doesn't clear
  `pendingReissues[tokenId]` if one exists. Not exploitable — `confirmReissue()` independently
  re-checks `certificates[oldTokenId].status == Active` and correctly reverts on a revoked
  certificate — but the stale entry lingers until someone calls `cancelReissueProposal()`
  (issuer/admin still can, since `Certificate.issuer` isn't wiped by revoke). Pure storage
  hygiene, zero security impact; a one-line `delete pendingReissues[tokenId]` in `revoke()` would
  tidy it up.

- **`registerPlots()` front-running of never-before-seen plot IDs by a rogue issuer.** Confirmed
  this works exactly as your own comments describe and mitigate: any `ISSUER_ROLE` holder can
  register a brand-new plot ID string before its rightful issuer does, but `adminReassignPlot()`
  exists as the documented admin escape hatch, and a sold plot (`activeTokenForPlot != 0`) is
  correctly untouchable either way. This is accepted, disclosed design, not a new finding —
  confirming it holds as documented, not flagging it.

## What I checked and found *not* to be a bug

- **Reentrancy:** every state-changing function (`issue`, `_executeReissue`, `revoke`) writes all
  sensitive state (`activeTokenForPlot`, `certificates[...]`, `Status`) *before* the trailing
  `_safeMint`/`_burn` calls that could hand control to an external contract. A malicious
  `to` re-entering during `onERC721Received` sees fully-consistent post-state and can't
  double-process anything (e.g. re-entrant `issue()` for the same plot correctly reverts on
  `activeTokenForPlot[plotId] != 0`).
- **Soulbound enforcement:** `_update()` correctly blocks `from != 0 && to != 0` transfers while
  still permitting mint/burn; `approve`/`setApprovalForAll` are hard-reverted; `getApproved`
  always returns zero; `isApprovedForAll` always returns false. No transfer path survives.
  Confirmed the `_update` override signature matches OZ v5's exactly (compiler would have
  flagged a mismatched override — it didn't).
- **Sale flow:** `approveSale()` is owner-gated and `reissue(SALE)` checks
  `saleApprovedBuyer[oldTokenId] == to` — this one genuinely ties the reissue to independent
  owner consent and isn't subject to the Finding #1 pattern.
- **`LOST_WALLET` reissues** always require admin confirmation unconditionally — not affected by
  Finding #1's beneficiary-substitution trick (there's no beneficiary check in that branch at
  all).

## Summary

| # | Finding | Severity | Status |
|---|---|---|---|
| 1 | Issuer can self-set `beneficiaryOf` then immediately reissue INHERITANCE, bypassing admin confirmation entirely | **Critical** | Fix drafted, compiled, exploit-retested closed, fast-path regression-tested clean |
| 2 | `onlyRole(ISSUER_ROLE)` on `issue`/`reissue`/`revoke`/`registerPlots` makes documented admin fallback unreachable | **Medium** | Fix drafted, compiled, exploit-retested closed |
| 3 | Pending reissue proposals silently overwritten, no explicit cancel required | **Low/Medium** | Fix drafted, compiled, exploit-retested closed |
| — | Unbounded issuer-supplied string lengths (estateName/plotId/surveyPlanNumber/coordinates) | Low (informational) | Not fixed — recommend a length cap like `logoSvgPath`'s |
| — | ASCII-only string sanitization (Unicode homoglyph spoofing) | Low (informational) | Already disclosed by your own comments; no action taken |
| — | Dangling `PendingReissue` after `revoke()` | Informational | Not fixed — no security impact, cosmetic cleanup only |

Findings #1–#3 come with compiled, test-verified fixes (both "exploit now blocked" and
"legitimate behavior unchanged" were checked, not just the diff read). If you want, I can turn
the patched contract into a proper PR-ready diff against the original file — I left the original
untouched for this review, per your request, and did all patching/exploit work on scratch copies.
