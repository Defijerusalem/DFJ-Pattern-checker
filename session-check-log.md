# Session-Start Check Log

Each entry below is produced by SKILL.md's Step -1 (session-start recent-hacks check). This is a
running log, newest entry first. Entries are draft findings for human review — nothing in this
file has been added to any reference file automatically.

---

## 2026-07-16 — Candidate: preview/execution divergence on fee- or loss-bearing withdrawal paths

**Apparent mechanism:** a vault's `preview*` function (e.g. `previewWithdraw`/`previewRedeem`) and its paired
state-changing function (`withdraw`/`redeem`) are implemented as two independent code paths rather than
sharing one fee/loss-calculation helper. The preview promises a fee-free/loss-free amount; the real
execution path applies a fee or a realized/unrealized loss haircut the preview didn't model. If a
same-transaction check still asserts the original (unadjusted) previewed amount, the withdrawal reverts
rather than silently underpaying — a narrow, easy-to-miss DoS on the withdrawal path rather than a fund-loss
bug.

**Evidence status (why this is logged here and not yet a Pattern):** one confirmed, independently-verified
case so far — **BakerFi** (Code4rena Invitational, December 2024): direct read of the actual contest source
(`code-423n4/2024-12-bakerfi/contracts/core/VaultBase.sol`) confirms `previewWithdraw`/`previewRedeem` call
plain `convertToShares`/`convertToAssets` with no fee applied, while the real `withdraw`/`redeem` route
through `_redeemInternal`, which does apply a withdrawal fee (`getWithdrawalFee()`) — the exact mechanism
described above, verified primary-source, not a search-summary paraphrase. This is a real, dated,
pre-mainnet audit finding (same evidentiary category this library already accepts elsewhere, e.g. GoGoPool
ggAVAX in `yield-aggregator.md` Pattern 2 — "confirmed high-severity audit finding, mitigated" rather than a
live hack).

A second candidate (Sommelier Cellars, 0xMacro audit A-3, Aug–Oct 2022) was checked and rejected: the source
page 403s, and the only available description reads as an open design-tradeoff the auditors asked the team
to document (which of two approaches to pick for `previewRedeem`/`convertToAssets`), not a confirmed,
reachable bug with the same preview-promises-X/execution-enforces-X-and-reverts mechanics. Not counted.

This library's own practice elsewhere (e.g. the first-depositor variant of Pattern 2) holds a mechanism to a
"two independent, real, confirmed cases" bar before writing it up as a full Pattern with match criteria. One
confirmed case is not yet two — still logged here, not promoted.

**Relates to:** `yield-aggregator.md` Pattern 2 (share-price math correctness) — same family (vault
accounting can silently diverge from real backing/payout), different specific trigger (fee/loss omission in
a preview function vs. donation-manipulable raw balance).

**Next step:** if a second independent, primary-source-verifiable case turns up naturally in future work,
promote this to a full pattern entry in `yield-aggregator.md`. Until then, leave it here.
