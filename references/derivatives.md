# Derivatives/Perpetuals Pattern Library

Validated against: Hyperliquid community vault drains (3 incidents, 2025), including the November 2025 POPCAT incident ($4.9M bad debt); Gains Network/gTrade (EXACT MATCH — quantified leverage/vault-depth mismatch up to 500x against a $19.3M vault, with the Luna/UST 2022 event confirming the designed backstop was disabled precisely when needed). Confirmed out-of-scope case: GMX V1 ($42M, July 2025) — reentrancy/vault accounting bug in legacy code, same category as Euler, belongs in Universal Core, not here. Dry-run tested against dYdX v4 (Cosmos-native L1 — confirmed clean on both patterns, with strong validated NOT PRESENT examples for leverage/liquidity calibration and oracle aggregation).

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

## Pattern 2 (lower confidence, secondary trigger): Oracle/Mark Price Latency Under Leverage

**What to check:** whether the mark price used for liquidations can be influenced by a transient price spike on a single source exchange/feed, given that leveraged positions amplify the consequence of even small price discrepancies.

**Confidence note:** this trigger is real and mechanistically sound but lacks a single named, dated incident in this library (distinct from the general mechanism description). Treat findings here as SIMILAR MATCH / watch-item status, not EXACT MATCH, until a specific case validates the point allocation.

**How to check:**
- Identify the mark price source(s). Single-exchange feeds with no aggregation across multiple venues are a higher-risk configuration.
- Check whether the index/mark price construction weights any single source disproportionately.

**What a genuine NOT PRESENT looks like (concrete example):** dYdX v4 aggregates mark price across seven independent exchanges (Binance, Bitfinex, Bitstamp, Bybit, Coinbase, crypto.com, GateIO) via validator-run oracle feeds with consensus aggregation every block — multi-source, not single-exchange. This is the kind of disclosed, verifiable aggregation that should clear NOT PRESENT; contrast with a protocol that discloses only one named price source for liquidation-triggering mark price.

## Pattern 3 (lower confidence, disclosed risk but not yet incident-validated): Asymmetric/Binary Settlement Risk

**What to check:** for prediction-market-style or binary-outcome perpetual markets (settling at a fixed extreme value depending on a real-world outcome, rather than tracking a continuously-priced asset), whether capital and leverage are likely to be asymmetric across the two sides of the bet, and what happens if the winning side cannot be fully paid out.

**Why this is flagged at lower confidence:** this is a disclosed structural risk, not yet a confirmed loss incident in this library. dYdX's own documentation for its TRUMPWIN market acknowledges that because capital invested on either side is generally unequal, and leverage can differ on each side, there is a possibility that there will not be enough money to fully pay out a leveraged bet on the winning side — which can force forced de-leveraging of accounts that are underwater before final settlement. This is a real, named, disclosed risk, but treat it as SIMILAR MATCH / watch-item status, not EXACT MATCH, until a specific realized loss event validates it.

**How to check:**
- Identify whether the market in question settles at a fixed extreme value tied to a real-world binary outcome, rather than tracking a continuous market price.
- Check whether the protocol discloses how it handles a payout shortfall (de-leveraging mechanism, insurance fund draw, socialized losses) and whether that mechanism is documented before the fact rather than improvised during settlement.

**Match criteria:**
- SIMILAR MATCH (ceiling for this pattern currently): binary/prediction-style market exists with a disclosed but untested payout-shortfall mechanism.
- NOT PRESENT: market is not binary/extreme-settlement in nature, or a payout-shortfall mechanism exists and has been tested in a real settlement event without issue.

## What this file does NOT cover

- Pure smart contract logic bugs in vault accounting (reentrancy, accounting errors) — see GMX V1, a confirmed Universal Core case, not a category-specific one.
- Funding rate mechanism design and its economic incentive properties — a design/tuning question, not a pattern-matchable vulnerability unless a specific manipulation case validates a concrete trigger.
