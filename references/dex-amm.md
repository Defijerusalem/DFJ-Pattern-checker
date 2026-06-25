# DEX/AMM Pattern Library

Validated against: Cetus Protocol ($223M, May 2025), KiloEx ($7M, 2025, across Base/BNB Chain/Taiko), PancakeSwap BCE/USDT pool ($679K, March 2025). Dry-run tested against Curve Finance (confirmed strong, manipulation-resistant EMA oracle design; surfaced the Harvest Finance downstream-integrator-misread distinction now built into Pattern 1) and Osmosis (Cosmos-native; JoinPoolNoSwap accounting bug, $5M, June 2022 — confirmed correctly out-of-scope as a code-logic bug, not a category-specific pattern, same boundary as Euler).

## Global evidence-quality standard

A clean NOT PRESENT requires a specific, checkable architectural fact — confirmed TWAP usage in the actual pricing function, a named oracle integration, documented pool depth relative to typical trade size. Vendor language ("battle-tested AMM," "secure pricing mechanism," "audited and trusted") is never sufficient on its own. If only this kind of language is available, output SIMILAR MATCH, not NOT PRESENT.

## Pattern 1: Spot-Price-Only Pricing (No TWAP)

**What to check:** whether the protocol's pricing function reads the current-block spot price/reserve ratio directly, or uses a time-weighted average price (TWAP) that requires manipulation to be sustained across multiple blocks.

**Why this matters — real cases:**
- The general mechanism: an attacker uses a flash loan to fund a massive single-block swap that distorts an AMM pool's spot price, then exploits that distorted price elsewhere (in the same pool, or in another protocol that reads this pool's price) before reversing the trade in the same transaction. The cost of the attack is bounded by flash loan fees; the profit is bounded only by how much value depended on the manipulated price.
- Cetus Protocol lost $223M and KiloEx lost $7M across three chains in 2025 to this category of oracle/price manipulation attack — both involving the same fundamental weakness of trusting a manipulable instantaneous price.

**How to check:**
- Locate the pricing function in the contract (often named something like `getPrice`, `_getReserves`, or similar).
- Check whether it reads `reserve0/reserve1` (or equivalent) directly from the current block, or whether it averages price over a window of blocks/time (TWAP).
- Check pool depth (total liquidity) relative to typical trade sizes the protocol expects — a thin pool is manipulable with less capital.

**Match criteria:**
- EXACT MATCH: pricing function uses current-block spot price with no time-averaging, AND this price is used as an oracle input for another function (lending, liquidation, derivative settlement) either within the same protocol or by an external integrator.
- SIMILAR MATCH: TWAP exists but the averaging window is short enough to be questionable (e.g., under 10 minutes), or TWAP implementation details are undisclosed.
- NOT PRESENT: confirmed TWAP or equivalent manipulation-resistant pricing with a documented, reasonable time window (verify in code, not just claimed in docs).

**Critical distinction — check this separately, even when Pattern 1 above clears NOT PRESENT:** a protocol's own pricing mechanism being manipulation-resistant does not mean every consumer of that pool's data is safe. Harvest Finance was exploited for ~$500K (in repeated $50M flash-loan cycles) by reading a Curve pool's *live reserve ratio* directly, instead of Curve's actual manipulation-resistant oracle value — Curve's own pricing was never at fault, but a downstream integrator read the wrong number. When checking any protocol that consumes price data from an external pool (rather than using its own internal pricing), explicitly verify it reads the smoothed/resistant oracle output, not a raw spot balance or reserve ratio. Standard audits often miss this because it's an architectural/integration choice, not a bug in either contract individually. Score this as a SIMILAR or EXACT MATCH against Pattern 1 even if the source pool itself is well-designed, if the integration method reads the unprotected value.

Also check for asset-specific oracle gaps: some manipulation-resistant oracles do not automatically account for yield-bearing or rebasing wrapped tokens (e.g., an oracle may return the underlying asset's price rather than a yield-bearing derivative's actual value including accrued yield). If the protocol integrates such an asset, verify the integration manually accounts for the conversion rate — an unverified assumption here is a SIMILAR MATCH, not NOT PRESENT.

## Pattern 2: Pool Ratio Distortion via Auxiliary Mechanism (Burn/Fee/Donation)

**What to check:** whether any auxiliary pool mechanism (token burn, fee redistribution, reward distribution) can be triggered or amplified by an external actor in a way that distorts the pool's price ratio independent of an actual trade.

**Why this matters — real case:**
- PancakeSwap's March 2025 BCE/USDT exploit: attackers deployed malicious contracts that bypassed buy/sell limits and manipulated the pool's token burn mechanism, artificially distorting the BCE/USDT ratio to create an arbitrage opportunity — a $679K loss. This is distinct from Pattern 1: the manipulation vector was the burn mechanism itself, not a flash-loan-funded spot price swing.

**How to check:**
- Identify any non-swap mechanism that alters pool token balances (burns, fee skims, auto-compounding, rebasing).
- Check whether that mechanism can be triggered by an external caller, or whether its trigger conditions can be gamed (e.g., triggering a burn repeatedly in quick succession before the pool can rebalance via arbitrage).

**Match criteria:**
- EXACT MATCH: an externally-triggerable auxiliary mechanism exists that directly alters pool ratio and has no rate-limiting or access control.
- SIMILAR MATCH: mechanism exists with some access control or rate-limiting, but the limit's adequacy is unverified.
- NOT PRESENT: no externally-triggerable balance-altering mechanism beyond standard swap function, or such mechanisms are restricted to a verified, access-controlled role.

## What this file does NOT cover

- MEV/sandwich attack exposure at the user-transaction level — this is a real, distinct risk category but operates on individual trades rather than protocol-level pool integrity; treat as a separate, lower-severity note rather than a pattern match here unless a specific case validates point allocation.
- Impermanent loss as a risk to LPs — this is a known, disclosed economic property of AMMs, not a security vulnerability, and should not be penalized as if it were a flaw.
