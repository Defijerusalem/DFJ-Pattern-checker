# Session-Start Check Log

Each entry below is produced by SKILL.md's Step -1 (session-start recent-hacks check). This is a
running log, newest entry first. Entries are draft findings for human review — nothing in this
file has been added to any reference file automatically.

---

## 2026-07-21 — Candidate: compromised off-chain oracle-signer key forging arbitrary attested prices (Ostium, ~$18M, July 2026)

**Apparent mechanism (per search-summary sources only — Halborn's incident writeup and CoinDesk's
coverage; not yet independently verified against primary transaction data or Ostium's own contracts):**
Ostium (an Arbitrum-based perpetuals exchange) relies on a price oracle that signs price attestations
off-chain before they are pushed on-chain. The attacker obtained the oracle's private signing key
(the specific compromise vector is not stated in the summaries reviewed) and used it to sign and
submit fabricated price reports — reportedly opening a position at a fake BTC price of ~$5,000, then
closing it once the feed reverted to the real market price of ~$60,000, netting the ~$18M gap.

**Why this is logged rather than checked against an existing pattern:** `derivatives.md` Pattern 2
("Oracle/Mark Price Latency Under Leverage") covers a *legitimate* feed being stale or lagging under
fast-moving conditions — a timing/latency problem. This is a distinct mechanism: the feed's signing
key itself was compromised, letting an attacker forge an arbitrary, fully-fabricated price with no
staleness or latency involved at all. `bridge.md`'s signing-interface-spoofing entries (Radiant,
Bybit) and its key-custody patterns are the closest existing relatives in this library, but those are
scored under the Bridge category specifically for cross-chain message signing, not a derivatives
protocol's own price-attestation oracle. This looks like a real, checkable, and currently
uncovered precondition (single/insufficiently-guarded oracle signing key with no on-chain sanity
bound on reported price movement) rather than a fit for any existing pattern's match criteria as
written.

**Evidence status:** one incident, sourced from secondary reporting (Halborn, CoinDesk) only — not
yet checked against Ostium's own contracts or a primary transaction trace. Per this library's
two-independent-case bar, this is not yet promotable to a scored pattern even if the mechanism is
confirmed accurate.

**Relates to:** `derivatives.md` Pattern 2 (adjacent but mechanically distinct — compromised signer
vs. stale-but-legitimate feed); `bridge.md`'s key-custody/signing-interface-spoofing family (same
general shape — a trusted off-chain signer being the actual point of failure — but for a price
oracle rather than a bridge relayer/multisig).

**Next step:** if a second independent case of a compromised/insufficiently-guarded oracle signing
key forging an arbitrary (not just stale) price turns up, and Ostium's own mechanism can be verified
against primary source (contracts, transaction trace, or an authoritative post-mortem) rather than
secondary summaries, consider a new Derivatives (or cross-cutting) pattern for "oracle signer key
compromise" distinct from Pattern 2's latency framing. Until then, leave it here.

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
