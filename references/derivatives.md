# Derivatives/Perpetuals Pattern Library

Validated against: Hyperliquid community vault drains (3 incidents, 2025), including the November 2025 POPCAT incident ($4.9M bad debt); Gains Network/gTrade (EXACT MATCH — quantified leverage/vault-depth mismatch up to 500x against a $19.3M vault, with the Luna/UST 2022 event confirming the designed backstop was disabled precisely when needed); KiloEx ($7.4M, April 2025), the October 2025 market-wide liquidation cascade ($19.3B), and Mango Markets (October 2022, $117M — a self-referential variant, where the attacker's own concentrated position and thin-market price manipulation fed back into their own collateral valuation) — three independent confirmations of Pattern 2's mark-price mechanism, spanning both externally manipulated single-source feeds and self-inflicted mark-price distortion; dYdX's TRUMPWIN-USD market (Oct–Nov 2024) and its own 2025 World Series perpetual announcement (confirming a direct, named ADL process fix and proposed compensation following TRUMPWIN) — two confirmations at the same protocol of Pattern 3's asymmetric/binary settlement mechanism, promoted from watch-item status. Confirmed out-of-scope case: GMX V1 ($42M, July 2025) — reentrancy/vault accounting bug in legacy code, same category as Euler, belongs in Universal Core, not here. Dry-run tested against dYdX v4 (Cosmos-native L1 — confirmed clean on Patterns 1 and 2, with strong validated NOT PRESENT examples for leverage/liquidity calibration and oracle aggregation).

## Global evidence-quality standard

A clean NOT PRESENT requires a specific, checkable fact — actual order book depth data for a given pair, disclosed maximum leverage per pair, or a documented liquidation engine design. Vendor language ("deep liquidity," "robust risk engine," "institutional-grade") is never sufficient on its own. If only this kind of language is available, output SIMILAR MATCH, not NOT PRESENT.

## Pattern 1: Leverage/Liquidity Mismatch on Thin Order Books

**What to check:** whether a trading pair offers high leverage (commonly 20x or higher) relative to that specific pair's actual on-chain or order-book liquidity depth — not the platform's aggregate liquidity, but the liquidity available for that specific pair.

**Why this matters — real case:**
- Hyperliquid's community-funded liquidity vault was drained three separate times in 2025 through coordinated attacks on low-liquidity tokens, with the repeatable mechanism being: high leverage offered on a pair, thin actual order book depth for that pair, and a community-funded liquidation pool that absorbs the resulting bad debt. The November 2025 POPCAT incident alone created $4.9M in bad debt.
- This is a structural, repeatable pattern at the same protocol, not a one-off — the pattern recurred because the underlying mismatch (leverage availability decoupled from real liquidity) was not corrected after the first incident.

**How to check:**
- For the specific pair in question, find the maximum leverage offered.
- Find the actual liquidity depth for that pair (order book depth, AMM pool size, or open interest relative to available counterparty liquidity) — not the platform's total TVL, which is not the same thing.
- Calculate whether a position near the maximum offered leverage could move the market significantly on its own, or whether liquidating such a position would require more liquidity than the pair actually has.

**Match criteria:**
- EXACT MATCH: high leverage (20x+) is offered on a pair where the position size enabled by that leverage exceeds a reasonable fraction (e.g., >10-20%) of that pair's actual available liquidity.
- SIMILAR MATCH: leverage/liquidity data is partially available but insufficient to calculate the ratio with confidence — e.g., aggregate TVL is known but per-pair depth is not disclosed.
- NOT PRESENT: leverage limits are calibrated to per-pair liquidity (e.g., lower leverage caps on thinner pairs), verified via the protocol's own risk parameters rather than asserted in marketing copy.

**What a genuine NOT PRESENT looks like (concrete example, not just absence of the bad pattern):** dYdX's maximum leverage decreases linearly with position size after a defined threshold, and available leverage on isolated markets is explicitly tied to current open interest — meaning leverage caps tighten dynamically as a market's actual trading activity changes, rather than being a static number set once regardless of real depth. This is the kind of disclosed, checkable mechanism that should clear NOT PRESENT — contrast with a protocol that simply states a fixed leverage cap with no stated relationship to liquidity or open interest, which should be treated as SIMILAR MATCH pending verification of how that cap was set.

## Pattern 2: Oracle/Mark Price Latency Under Leverage

**What to check:** whether the mark price used for liquidations can be influenced by a transient price spike on a single source exchange/feed, given that leveraged positions amplify the consequence of even small price discrepancies.

**Why this matters — real cases, independently confirmed three times:**
- KiloEx ($7.4M, April 2025): a price oracle issue allowed an attacker to create a new leveraged position exploiting the flawed price feed, draining funds across Base, opBNB, and BSC deployments before the protocol could pause. A confirmed, single-protocol, dollar-quantified exploit of exactly this mechanism.
- October 2025 market-wide liquidation cascade ($19.3B in liquidations across the industry): oracle manipulation allowed a $60M sell-off of USDe to trigger cascading liquidations, exploiting pricing mechanisms tied to a manipulable spot-market data source rather than an independently aggregated valuation. While broader in scope than a single-protocol exploit, this confirms the same root mechanism — a mark price too dependent on a single, manipulable source — at a scale that demonstrates the failure mode is systemic, not theoretical.
- Mango Markets (October 2022, $117M): a distinct sub-mechanism worth naming separately — the attacker did not passively read a manipulable external feed. They opened a large, concentrated MNGO-PERP position, then used a comparatively small amount of capital to pump MNGO's thin spot market, which fed directly into the mark price used to value their own perpetual position as collateral. They then borrowed against that self-inflated collateral value. This confirms the pattern applies not only to externally manipulated single-source feeds (KiloEx, October 2025 cascade) but also to a protocol's own mark price being distorted by a position-holder who is simultaneously the price-mover — a self-referential version of the same underlying weakness: a mark price too dependent on a thin, single source that any sufficiently funded party can move.

**How to check:**
- Identify the mark price source(s). Single-exchange feeds with no aggregation across multiple venues are a higher-risk configuration.
- Check whether the index/mark price construction weights any single source disproportionately.
- Check whether margin settlement or liquidation triggers are tied directly to a spot price that could itself be distorted (e.g., a wrapped-asset exchange rate diverging from true value during a stress event), rather than an independently verified valuation.
- Check specifically whether a single position-holder's own trading activity (in the underlying spot market or a thin derivatives market) could plausibly move the price feed their own collateral or position is valued against — the Mango Markets self-referential variant of this pattern.

**What a genuine NOT PRESENT looks like (concrete example):** dYdX v4 aggregates mark price across seven independent exchanges (Binance, Bitfinex, Bitstamp, Bybit, Coinbase, crypto.com, GateIO) via validator-run oracle feeds with consensus aggregation every block — multi-source, not single-exchange. This is the kind of disclosed, verifiable aggregation that should clear NOT PRESENT; contrast with a protocol that discloses only one named price source for liquidation-triggering mark price.

**Match criteria:**
- EXACT MATCH: mark price construction relies on a single exchange or single data source for liquidation-triggering valuations, with no aggregation or independent cross-check, and no disclosed mitigation.
- SIMILAR MATCH: some aggregation exists but is undisclosed in detail, weights a single source disproportionately, or has not been independently verified to function as claimed under stress.
- NOT PRESENT: confirmed, disclosed multi-source aggregation (verify in documentation/code, not just claimed) with no single point of price-data failure.

## Pattern 3: Asymmetric/Binary Settlement Risk

**What to check:** for prediction-market-style or binary-outcome perpetual markets (settling at a fixed extreme value depending on a real-world outcome, rather than tracking a continuously-priced asset), whether capital and leverage are likely to be asymmetric across the two sides of the bet, and what happens if the winning side cannot be fully paid out.

**Why this matters — confirmed twice at the same protocol, one year apart:** dYdX's own TRUMPWIN market (Oct\u2013Nov 2024) acknowledged that because capital invested on either side is generally unequal, and leverage can differ on each side, there is a possibility that there will not be enough money to fully pay out a leveraged bet on the winning side, forcing auto-deleveraging (ADL) of underwater accounts before final settlement. This was disclosed as a real risk, not yet confirmed. One year later, dYdX's own announcement for its 2025 World Series perpetual confirmed the risk had materialized in practice: the team stated they were \u201cfocused on improving... the auto-deleveraging (ADL) process to make it smoother and more predictable for traders\u201d as a direct, named lesson from TRUMPWIN, and proposed a real compensation mechanism for \u201clost profits due to ADL\u201d \u2014 confirming ADL shortfalls were severe enough in TRUMPWIN to require an active process fix and a proposed reimbursement a year later. Two real, dated instances at the same protocol meet this methodology's validation bar (the same standard Cream Finance's two same-protocol incidents met for Lending Pattern 2).

**How to check:**
- Identify whether the market in question settles at a fixed extreme value tied to a real-world binary outcome, rather than tracking a continuous market price.
- Check whether the protocol discloses how it handles a payout shortfall (de-leveraging mechanism, insurance fund draw, socialized losses) and whether that mechanism is documented before the fact rather than improvised during settlement.
- Check whether a prior binary-settlement event at this protocol required a real, after-the-fact remediation or compensation proposal \u2014 a direct sign the disclosed risk previously materialized.

**Match criteria:**
- EXACT MATCH: a binary/prediction-style market with a documented payout-shortfall mechanism has had a real settlement event in which the mechanism was insufficient, requiring after-the-fact remediation or compensation, with no subsequent process fix confirmed.
- SIMILAR MATCH: binary/prediction-style market exists with a disclosed but untested payout-shortfall mechanism, or a prior shortfall event occurred but a documented process fix has since been implemented.
- NOT PRESENT: market is not binary/extreme-settlement in nature, or a payout-shortfall mechanism exists and has been tested in a real settlement event without issue.

## What this file does NOT cover

- Pure smart contract logic bugs in vault accounting (reentrancy, accounting errors) — see GMX V1, a confirmed Universal Core case, not a category-specific one.
- Funding rate mechanism design and its economic incentive properties — a design/tuning question, not a pattern-matchable vulnerability unless a specific manipulation case validates a concrete trigger.
