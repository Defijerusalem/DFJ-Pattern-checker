# Yield Aggregator Pattern Library

Validated against: Yearn legacy vault exploit ($9M, December 2, 2025) and Yearn yETH pool exploit ($9M, November 30, 2025) — two distinct incidents, three days apart, same protocol, different root causes. Dry-run tested against Beefy Finance (confirmed strong, tested-not-theoretical panic mechanism for Pattern 1; surfaced the underlying-protocol risk-inheritance rule now in SKILL.md) and Volo/Navi (Sui, Move-based — confirmed the failure category (access/key management, not exotic Move-specific logic) transfers cleanly across chain architectures; also a real example of a protocol pledging to absorb a loss rather than socializing it).

## Global evidence-quality standard

A clean NOT PRESENT requires a specific, checkable fact — a disclosed, executable kill-switch mechanism for deprecated strategies, or verified vault accounting logic that doesn't depend on raw, donatable balances. Vendor language ("actively managed," "rigorously monitored strategies," "battle-tested vaults") is never sufficient on its own. If only this kind of language is available, output SIMILAR MATCH, not NOT PRESENT.

## Before applying any pattern below: check for inherited risk from underlying protocols

A yield aggregator's vault wraps an underlying protocol (a lending market, a DEX pool, a staking contract). The aggregator's own contract can be clean while the underlying protocol it deposits into carries real risk. Before checking Patterns 1 and 2 below, identify what underlying protocol(s) the vault/strategy interacts with, and check that underlying protocol against the relevant other reference file (`lending.md` for a vault depositing into a lending market, `dex-amm.md` for a vault providing liquidity to a DEX pool, etc.). Any unresolved EXACT MATCH or SIMILAR MATCH finding on the underlying protocol should be carried forward and disclosed as inherited risk on the aggregator vault, even if the vault's own wrapping logic passes Patterns 1 and 2 cleanly. This mirrors how some platforms in this space explicitly flag underlying-platform risks as automatically inherited by every product built on top, regardless of whether the wrapping product separately discloses them.

## Pattern 1: Deprecated/Legacy Strategy Retirement Risk

**What to check:** whether the protocol has older, superseded vault versions or strategies that remain live and holding user funds, and whether governance has a genuinely *executable* path to force-retire them — not just a theoretical one.

**Why this matters — real case:**
- Yearn's December 2, 2025 exploit ($9M) targeted a known governance problem: who has authority and responsibility to decommission deprecated, vulnerable code. Early vault contracts had emergency shutdown mechanisms, but executing them required governance votes that never reached consensus — the vulnerable vaults simply continued existing, holding millions in user deposits, because the kill-switch existed on paper but couldn't actually be triggered in practice. The specific vulnerability involved how the deprecated vaults obtained price information (calling a DEX directly for prices, an outdated pattern superseded in newer versions).
- This is a process/governance failure, not a hidden code flaw — the vulnerability wasn't secret, the gap was that no one could act on the knowledge fast enough.

**How to check:**
- Identify whether the protocol has multiple live vault/strategy versions, and whether older versions use outdated patterns (e.g., direct DEX price reads instead of TWAP, deprecated dependency versions).
- Check whether an emergency shutdown/deprecation mechanism exists, AND whether it has actually been used or tested — a mechanism that exists in code but has never been triggered, especially if it requires a governance vote with no enforced timeline, should not be treated as equivalent to a real, executable safeguard.
- Check published vault/strategy risk scores if the protocol maintains one (some established platforms publish internal risk-scoring for this exact purpose — treat the existence of such a score as a positive signal, but verify it's actually being acted on, not just published).

**Match criteria:**
- EXACT MATCH: deprecated/legacy strategies are confirmed live with user funds, use outdated/known-risky patterns, and the deprecation mechanism requires an unresolved governance process with no enforced deadline.
- SIMILAR MATCH: legacy strategies exist but a shutdown mechanism has either been used successfully before or has a disclosed, time-bound execution path.
- NOT PRESENT: no live deprecated strategies holding meaningful user funds, or all legacy strategies have been actively, successfully migrated/shut down.

## Pattern 2: Donation-Manipulable Vault Share-Price Math

**What to check:** whether a vault's share price (the exchange rate between deposited tokens and vault shares) is calculated from a raw, directly-donatable balance rather than an internally-tracked accounting value.

**Why this matters — related case (Lending category, same root mechanism):**
- This pattern is the same underlying mechanism validated in `lending.md` Pattern 2 via Cream Finance's October 2021 exploit, where a Yearn vault token's exchange rate could be manipulated by donating assets directly to the underlying vault. It applies equally here because yield aggregators are the primary issuers of this type of share-price-bearing vault token.
- Separately, Yearn's own November 30, 2025 yETH exploit ($9M) involved a related but distinct mechanism: manipulation of an iterative fixed-point solver used for LP token minting, causing invariant breakdown and arithmetic underflow. This is closer to a Universal Core code-logic issue (solver/math implementation flaw) than a donation-manipulation pattern specifically — flag separately and with lower confidence than Pattern 1 above.

**How to check:**
- Locate the function that calculates share price or exchange rate.
- Check whether it derives from `balanceOf(vaultAddress)` (a raw balance anyone can inflate by sending tokens directly) versus an internally-tracked deposit ledger.

**Match criteria:**
- EXACT MATCH: share price is calculated from a raw, externally-donatable balance with no internal accounting check.
- SIMILAR MATCH: internal accounting exists but edge cases (e.g., first-depositor scenarios, solver-based calculations) are present and not independently verified as safe.
- NOT PRESENT: share price is calculated purely from an internally-tracked deposit ledger, immune to direct balance donation.

## What this file does NOT cover

- Solver/iterative-math implementation bugs (the specific mechanism in Yearn's yETH incident) — this is closer to a novel code-logic flaw than a recognizable pattern; treat any finding here as a flag for professional audit review, not a confident pattern match, unless a second independent case validates a specific, checkable trigger.
- Strategy yield/APY sustainability and tokenomics — an economic design question, not a security pattern.
