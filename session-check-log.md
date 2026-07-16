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

**Evidence status (why this is logged here and not yet a Pattern):** no real, dated, press/research-covered
exploit has been confirmed for this mechanism specifically — only (a) a generic, non-attributed anecdote,
(b) the ERC-4626 spec's own documented caveat that preview functions must account for the same fees/slippage
the real call applies, and (c) OpenZeppelin's `ERC4626Fees.sol` reference mitigation, which exists to close
this exact gap. None of these is a checkable incident, so this does not yet clear this project's
evidence-quality bar (real, dated exploit(s) — the same "two-incident" standard applied elsewhere in this
library before a mechanism becomes a full Pattern with match criteria).

**Relates to:** `yield-aggregator.md` Pattern 2 (share-price math correctness) — same family (vault
accounting can silently diverge from real backing/payout), different specific trigger (fee/loss omission in
a preview function vs. donation-manipulable raw balance).

**Next step:** search for a real, named incident actually caused by this specific divergence (a vault
withdrawal DoS or fund-loss traceable to a preview function omitting a fee/loss the execution path applied)
before promoting this to a full pattern entry.
