# Frax Protocol — DFJ Pattern Checker Scan
**Date:** 2026-06-26

**Inputs used for this check:** Public protocol documentation, prior dry-run results referenced in this skill's own reference files (bridge.md Pattern 3 note and SKILL.md Concentrated Control Risk section both name Frax explicitly), and publicly known protocol architecture. No contract source code, audit reports, or on-chain subgraph queries were provided or performed. Findings that require on-chain data are marked CANNOT DETERMINE with the specific verification step needed.

---

## Step 1: Protocol Status

**Frax Protocol is operating normally.** No shut-down, formal wind-down, or active freeze as of this check. The December 2025 multisig event (an undisclosed contract patch pushed through the 3-of-5 team multisig, referenced in SKILL.md) was a transparency/governance incident, not a fund-draining exploit. Frax continues to operate with live TVL across multiple chains and products.

---

## Step 2: Protocol Categories

Frax spans four materially distinct product lines, scored separately:

| Product | Category | Reference File |
|---|---|---|
| FRAX / FPI stablecoin | Stablecoin/CDP | `stablecoin.md` |
| Fraxlend | Lending (isolated-market) | `lending.md` |
| Fraxswap | DEX/AMM | `dex-amm.md` |
| Cross-chain (Fraxferry + LayerZero OApps) | Bridge | `bridge.md` |

---

## Step 3: Inherited Risk

**Fraxlend → FRAX dependency:** Fraxlend's primary debt denomination is FRAX. Any peg instability in FRAX (see Stablecoin findings below) is inherited risk for all Fraxlend positions. A FRAX depeg cascades directly into borrower health factors and liquidation mechanics.

**frxETH / sfrxETH as collateral (Ethereum mainnet):** frxETH is a native Ethereum LST — deposit ETH, receive frxETH; ETH is staked by Frax validators. On Ethereum mainnet, sfrxETH as Fraxlend collateral is *not* cross-chain-bridge-dependent. The Lending Pattern 1 bridge-dependency trigger does not apply for that specific market.

**Bridged frxETH on other chains:** Cross-chain versions of frxETH (e.g., frxETH on Arbitrum or Base) depend on Frax's LayerZero OApp infrastructure. If bridged frxETH is accepted as Fraxlend collateral on other chains, lending risk and bridge risk compound at that market. This requires per-market verification (see Lending Pattern 1 below).

---

## Product 1: FRAX Stablecoin

### Pattern 1: Mint Authority Control Risk

**SIMILAR MATCH** — Evidence of privileged control over minting; contract-level caps unverified.

FRAX v3 minting flows through Algorithmic Market Operations (AMO) controllers — smart contracts that can mint and redeem FRAX within strategy parameters. These AMO contracts are governed by FXS token holders and, more immediately, by the 3-of-5 core team multisig controlling the Comptroller and Timelock (confirmed in SKILL.md — see Concentrated Control Risk below). That multisig can upgrade, pause, or reconfigure AMO strategies.

The mitigating factor is that FRAX v3 targets 100% collateralization, meaning minting is not intended to be uncapped or collateral-free. Whether AMO contract-level mint authorization enforces on-chain caps *independently of multisig intervention* — the bar for NOT PRESENT — could not be verified without contract code access. The December 2025 undisclosed patch demonstrates that the multisig can act without advance notice; claiming NOT PRESENT here without reviewing the AMO contracts directly would be overconfident.

**Evidence:** Frax Protocol documentation (AMO architecture); SKILL.md Concentrated Control Risk section (3-of-5 multisig, December 2025 patch).
**Confidence:** SIMILAR MATCH — honest ceiling without contract code.

---

### Pattern 2: Collateral Liquidity Depth Risk

**SIMILAR MATCH** — On-chain collateral liquid; RWA-backed portion not on-chain redeemable.

FRAX v3's on-chain portion (USDC, yield-bearing stablecoins) benefits from historically deep liquidity on Curve and Uniswap pools. The concern is the portion of FRAX backing that flows through FinresPBC, Frax's federally-regulated banking subsidiary holding U.S. Treasuries as reserves. That RWA portion contributes no on-chain redemption liquidity — it cannot be liquidated trustlessly in a market stress scenario. Without current on-chain liquidity depth data (no subgraph pull was performed), this is SIMILAR MATCH: a redemption mechanism exists but its capacity under stress through the off-chain RWA channel is unverified.

**Additional systemic note:** A large share of circulating FRAX supply is historically concentrated as liquidity within Curve pools, Fraxswap, and Fraxlend itself. Disruption to any of those venues (e.g., a Curve pool drain or Fraxlend cascade liquidation) could rapidly affect FRAX liquidity and peg stability — a real concentration risk worth noting even though it has no formal match criteria in this library yet.

**Confidence:** SIMILAR MATCH.

---

### Pattern 3: Off-Chain Operational/Counterparty Dependency Risk

**SIMILAR MATCH** (ceiling for this pattern — no EXACT MATCH criteria defined in this library).

FRAX v3 explicitly depends on FinresPBC — Frax's federally-regulated banking subsidiary — to hold U.S. Treasury bills and interest-bearing deposits as FRAX reserves. This is a direct, ongoing off-chain dependency: a regulatory action against FinresPBC, a bank-level freeze, or an inability to process redemptions would make that portion of FRAX's backing inaccessible regardless of what any smart contract says. The parallel to Ethena/USDe's custodian-and-exchange dependency is structural — a different type of off-chain institution, but the same risk category.

Frax's off-chain counterparty diversification is structurally limited by operating through a single subsidiary (FinresPBC). Reserve fund sizing for adverse scenarios and regulatory-freeze risk are not independently verifiable from public documentation.

**Evidence:** Frax Protocol v3 documentation (FinresPBC structure, RWA backing).
**Confidence:** SIMILAR MATCH.

---

## Product 2: Fraxlend (Isolated-Market Lending)

*Architecture note: Fraxlend is an isolated-market protocol — each market has independent collateral, oracle, and risk parameters. Pattern 1 must be applied per-market, not as a protocol-wide aggregate.*

### Pattern 1: Collateral Concentration in Cross-Chain-Dependent Assets

**CANNOT DETERMINE** (per-market) — On-chain market composition data not available in this check.

The meaningful check is per-market: identify active Fraxlend markets, determine each market's collateral asset, and for any bridged/wrapped asset trace its backing to the LayerZero OApp infrastructure (see Bridge findings). On Ethereum mainnet, sfrxETH-collateralized markets do not trigger this pattern (native ETH staking, not cross-chain). On Arbitrum, Base, or Fraxtal deployments using bridged frxETH as collateral, the bridge risk compounds — those markets would require a full Bridge Pattern 1 check for their specific LayerZero route.

**Specific next step:** Query Fraxlend's market list on each chain; for any market using a cross-chain asset as collateral, call `getConfig()` on the LayerZero Endpoint for that OApp address and chain EID.

**Confidence:** CANNOT DETERMINE.

---

### Pattern 2: Exotic/Non-Standard Token Integration Risk

**SIMILAR MATCH** — sfrxETH's yield-bearing mechanics require verified oracle handling.

sfrxETH (Frax's ERC-4626 staking vault token) is used as collateral in at least one Fraxlend market. It is not ERC-777 and its share price is not donation-manipulable in the classical Cream Finance sense — the per-share value is determined by the Frax ETH staking contract's internal accounting, not a raw `balanceOf()` read. However, the dex-amm.md Pattern 1 note is directly relevant: yield-bearing tokens require oracle integrations that explicitly account for the conversion rate (ETH → sfrxETH price, not just ETH price). If Fraxlend's sfrxETH oracle returns the underlying ETH price without applying the current sfrxETH/ETH exchange rate, collateral would be mispriced. This requires verified inspection of the oracle configuration for the sfrxETH/FRAX market.

**Evidence:** Fraxlend documentation (sfrxETH listed as accepted collateral); dex-amm.md asset-specific oracle gap note.
**Confidence:** SIMILAR MATCH — flag for review; cannot confirm clean oracle handling without contract code.

---

### Pattern 3: Curator/Allocator Risk

**NOT PRESENT** — Fraxlend is a direct-market protocol; users select specific isolated markets. No intermediary curator layer allocates depositor funds across markets on their behalf.

---

## Product 3: Fraxswap (DEX/AMM)

### Pattern 1: Spot-Price-Only Pricing

**SIMILAR MATCH** — TWAMM design provides structural manipulation resistance; external integrator behavior unverified.

Fraxswap is a Time-Weighted Average Market Maker (TWAMM): large orders are broken into infinitely many pieces executed continuously over a defined time window. This design is inherently more resistant to single-block flash-loan-funded manipulation than a standard AMM. However, Fraxswap does not natively provide the same TWAP oracle interface as Uniswap v2/v3. A downstream protocol reading Fraxswap's instantaneous reserve ratio as a price feed would still face standard single-block manipulation risk. Whether any external protocol reads Fraxswap pool state as a price reference could not be verified.

**Confidence:** SIMILAR MATCH — cannot confirm NOT PRESENT without verifying all downstream integrators.

---

### Pattern 2: Pool Ratio Distortion via Auxiliary Mechanism

**CANNOT DETERMINE** — TWAMM pending-order execution mechanics not analyzed at contract level.

**Confidence:** CANNOT DETERMINE.

---

## Product 4: Cross-Chain Infrastructure (Bridge)

*Frax uses LayerZero OApps for cross-chain token transfers (FRAX, frxETH, sfrxETH across Ethereum, Arbitrum, Base, Fraxtal, and others).*

**Note from bridge.md:** Frax (LayerZero-based) was explicitly included in prior dry-run testing of this pattern library. The findings below are consistent with those results.

### Pattern 1: Verifier/Validator Independent-Operator Count

**SIMILAR MATCH** — DVN configuration requires an on-chain contract call to verify; not accessible via documentation search.

Frax's cross-chain infrastructure is built on LayerZero. The actual DVN configuration is stored as contract state in the LayerZero Endpoint contract and requires calling `getConfig()` with Frax's specific OApp address, library address, and chain EID. This is a contract read, not a document search.

**Contextual baseline from bridge.md Pattern 1:** as of April 2026, approximately 47% of active LayerZero OApp contracts ran a 1-of-1 DVN configuration, representing over $4.5 billion in associated exposure. Whether Frax falls in the 47% or the 53% is unknown without the contract call.

**Specific next step:** Call `getConfig()` on the LayerZero v2 Endpoint (`0x1a44076050125825900e736c501f859c50fE728c`) using Frax's OApp address for each relevant chain pair and token route (FRAX, frxETH, sfrxETH).

**Confidence:** SIMILAR MATCH.

---

### Pattern 2: Failover/Degradation Behavior

**CANNOT DETERMINE** — No documented failover behavior for Frax's LayerZero integration is available in public sources.

**Confidence:** CANNOT DETERMINE.

---

### Pattern 3: Key Custody Architecture

**SIMILAR MATCH** — Confirmed by prior dry-run results in this pattern library.

From bridge.md Pattern 3 directly: *"Pattern 3 has not cleared to NOT PRESENT in any test run against this library — not LayerZero-based bridges (Stargate, Pendle, Frax)."* Key storage and distribution practices for privileged bridge admin roles in Frax's LayerZero deployment are undisclosed at the individual-operator level.

**Important framing:** This is an industry-wide finding — no bridge checked in this library has cleared Pattern 3 to NOT PRESENT. SIMILAR MATCH is the honest ceiling for nearly any bridge, not a Frax-specific differentiating weakness.

**Confidence:** SIMILAR MATCH (consistent with industry norm).

---

### Pattern 4: Detection/Response Time

**No incident history to evaluate.** Frax's cross-chain infrastructure has not experienced a documented major exploit. Cannot assess detection/response time capability without a real incident as reference.

---

### Pattern 5: Signing-Interface Spoofing

**SIMILAR MATCH** — Multisig confirmed; independent transaction verification practices undisclosed.

Frax's 3-of-5 core team multisig relies on a multisig interface for transaction review and approval. Whether signers independently verify transaction calldata through a channel separate from the primary signing interface — specifically, whether they can detect a delegatecall disguised as a routine transfer — is not publicly documented. The Radiant Capital and Bybit cases demonstrate that hardware wallets and a strong threshold do not protect against a compromised web interface.

**Confidence:** SIMILAR MATCH.

---

## Cross-Cutting Check 1: Concentrated Control Risk

**EXACT MATCH** — Directly named and confirmed in this skill's own reference material.

From SKILL.md, Concentrated Control Risk section (validating case): *"Frax's 3-of-5 core team multisig controlling the Comptroller and Timelock, which pushed an undisclosed contract patch in December 2025."*

**Assessment against EXACT MATCH criteria:**
- **Mechanism for severe unilateral action exists:** Yes — 3-of-5 admin multisig with authority over the Comptroller and Timelock, the root administrative controls for FRAX minting parameters, AMO strategies, and protocol upgrades.
- **Power is demonstrably concentrated:** Yes — all 5 signers are core team; only 3 are needed to execute. Effectively the same organization controlling a majority threshold with no independent outside veto.
- **Friction:** A Timelock exists, providing temporal delay. However, the December 2025 patch was pushed without public disclosure during the timelock window — demonstrating that the timelock provides delay but not transparency or independent community veto.
- **Real-world exercise:** Confirmed — the December 2025 undisclosed contract patch shows this mechanism was actually used.

All three EXACT MATCH criteria are met. The Comptroller and Timelock authority extends across FRAX minting, Fraxlend governance, and Fraxswap configuration — this is a root-level finding applying across all Frax product lines simultaneously.

**Evidence:** SKILL.md Concentrated Control Risk section (direct, named reference).
**Confidence:** EXACT MATCH — highest confidence finding in this scan.

---

## Cross-Cutting Check 2: Per-Chain Deployment Consistency

**CANNOT DETERMINE** — Protocol-wide.

Frax is deployed on Ethereum, Arbitrum, Optimism, Polygon, Base, Fraxtal, and other chains. The LayerZero DVN configuration is per-OApp, potentially varying by chain pair and token route — not confirmed identical across all deployments. Admin multisig composition may also differ per chain. Findings verified on Ethereum mainnet do not automatically apply to other deployments.

---

## Summary Table

| Product | Pattern | Status |
|---|---|---|
| FRAX Stablecoin | P1: Mint Authority Control | SIMILAR MATCH |
| FRAX Stablecoin | P2: Collateral Liquidity Depth | SIMILAR MATCH |
| FRAX Stablecoin | P3: Off-Chain Operational Dependency | SIMILAR MATCH |
| Fraxlend | P1: Collateral Concentration (cross-chain) | CANNOT DETERMINE |
| Fraxlend | P2: Exotic Token Integration (sfrxETH oracle) | SIMILAR MATCH |
| Fraxlend | P3: Curator/Allocator Risk | NOT PRESENT |
| Fraxswap | P1: Spot-Price-Only Pricing | SIMILAR MATCH |
| Fraxswap | P2: Pool Ratio Distortion | CANNOT DETERMINE |
| Bridge (LayerZero) | P1: Verifier Independence | SIMILAR MATCH |
| Bridge (LayerZero) | P2: Failover Behavior | CANNOT DETERMINE |
| Bridge (LayerZero) | P3: Key Custody | SIMILAR MATCH |
| Bridge (LayerZero) | P4: Detection/Response Time | No history |
| Bridge (LayerZero) | P5: Signing-Interface Spoofing | SIMILAR MATCH |
| Cross-cutting | **Concentrated Control Risk** | **EXACT MATCH** |
| Cross-cutting | Per-Chain Consistency | CANNOT DETERMINE |

---

## End Caveat

This check covers patterns validated against real, named, dated incidents. It does not find novel code-logic bugs — the Euler Finance case ($197M, 2023) is the reference: six professional audits missed it, and this pattern library would not have caught it either. "NOT PRESENT" across all patterns does not mean a protocol is safe — only that it was not flagged by this specific, limited check. For any capital-significant decision involving Frax Protocol, professional audit of the specific contracts in question — particularly Fraxlend's oracle handling for sfrxETH and AMO contract mint controls — remains necessary.

---

## Breakdown (plain language)

**What kind of result this is:** Frax is a large, actively operating, well-documented protocol. This scan found one confirmed finding (the governance control structure), several areas that need closer inspection, and several things we simply couldn't verify without direct contract access.

---

**Who's actually in charge:** Three Frax core team members, acting together, can push changes to the protocol's core settings without needing approval from anyone outside the team. In December 2025, they used that authority to push a software change without announcing it to the public first. Think of it like a company where three co-founders can quietly rewrite the rules governing how everyone's money is managed, without a required public notice period. This is the most clearly confirmed finding in this scan — not an accusation of wrongdoing, but a documented fact about how the power structure works. The technical term is an *admin multisig*: a shared key that requires agreement from a minimum number of holders before it can act.

---

**The stablecoin (FRAX):** FRAX is backed partly by assets held in a real bank that Frax itself controls, called FinresPBC, which holds U.S. Treasury bills as reserves. If that bank faced a regulatory problem or couldn't process withdrawals — due to a government action, a bank-level freeze, or similar — the assets inside it would be inaccessible regardless of what the software says. The on-chain portion of FRAX's backing doesn't have this problem, but the bank-held portion does. This type of dependency is called *off-chain counterparty risk*. We also couldn't independently confirm all the details of how FRAX minting is controlled at the contract level, which means there may be more to check here.

---

**The lending product (Fraxlend):** Fraxlend lets users borrow against collateral in isolated compartments — a problem in one market can't automatically spill into another, which is a sensible design. The thing to watch is how collateral assets are priced. Fraxlend accepts a staked Ethereum token (sfrxETH) as collateral; this type of token grows in value over time as staking rewards accumulate. The system's price feed needs to correctly account for that growth — if it reads the wrong number, the collateral could be valued incorrectly. We couldn't confirm whether the price feed handles this correctly without looking at the contract code directly. On chains other than Ethereum (like Arbitrum or Base), some Fraxlend collateral assets may be moved there via a bridge — which adds a layer of risk we also couldn't verify without on-chain data.

---

**Moving money between blockchains:** Frax uses a technology called LayerZero to move assets across different blockchains. LayerZero relies on outside parties called *verifiers* (grouped in what's called a *DVN* — Decentralized Verifier Network) to confirm that a transfer really happened before it gets processed on the other end, like witnesses signing off on a delivery. We couldn't confirm how many independent verifiers Frax requires, or whether they're genuinely separate organizations — this requires reading a specific value stored directly in Frax's contracts on-chain, which this text-based check can't do. For context: as of early 2026, nearly half of all protocols using this same technology were using only a *single* verifier with no backup. A $292M exploit in 2026 (a different protocol, KelpDAO) happened precisely because its bridge used a single verifier. We don't know whether Frax falls in the risky half or the safer half. The people holding the keys to Frax's bridge controls also haven't publicly disclosed how they secure those keys — though to be fair, no bridge in this scan's entire reference library has disclosed that either.

---

**The December 2025 governance event:** This scan's own reference material identifies a specific incident where Frax's core team pushed a software change to the protocol without publicly announcing it beforehand. This isn't classified as a hack — no funds were stolen — but it demonstrates that the power structure allows for changes that users and outside observers don't necessarily see coming. That's what the "confirmed finding" in this scan is about.

---

**The trading pool (Fraxswap):** Fraxswap is designed to execute large trades slowly over time rather than all at once, which makes it harder to manipulate prices. That's a more sophisticated design than standard trading pools. It's probably fine for Frax's own internal operations. If any outside system were reading Fraxswap's prices as a reference rate, it would need to be careful about *exactly how* it reads those prices — reading the wrong value from a pool is a documented way other protocols have lost money. We don't have confirmed evidence of this happening with Fraxswap, but couldn't confirm it isn't happening either.

---

*This only checks for a specific list of problems that have caused real losses before. It can't catch a brand-new kind of problem nobody has seen yet, and it doesn't mean the protocol is safe just because something didn't show up here.*
