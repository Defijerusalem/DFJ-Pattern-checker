# Stablecoin/CDP Pattern Library

Validated against: USR/Resolv Labs ($24M, 95% depeg, March 2026), StablR ($13.5M, May 2026, same root pattern two months apart), Angle Protocol/EURA (EXACT MATCH on Pattern 2 — 74% of USDC reserves deposited in Euler Finance via automated strategy, causing an immediate agEUR depeg when Euler was exploited in March 2023; protocol later entered formal wind-down), USDX/Stables Labs (EXACT MATCH on Pattern 3, first case defining this pattern's EXACT MATCH criteria — November 2025, peg fell over 55% below $0.45 when the Balancer V2 exploit disrupted liquidity its delta-neutral hedging strategy depended on, compounded by a documented failure to rebalance stale, concentrated, illiquid positions in the reserve portfolio for months prior). Validated negative result: apxUSD and MIM (June 2026) — both depegged the same week with no exploit, no compromised key, no unauthorized mint; collateral simply repriced under market stress. Dry-run tested against Ethena/USDe (confirmed strong NOT PRESENT example for Pattern 1; surfaced real liquidity-depth and reserve-fund gaps for Patterns 2 and 3).

## Global evidence-quality standard

A clean NOT PRESENT requires a specific, checkable fact — disclosed on-chain mint caps, a named multi-party minting authorization process, or verified collateral liquidity data. Vendor language ("fully backed," "secure minting process," "robust collateral framework") is never sufficient on its own. If only this kind of language is available, output SIMILAR MATCH, not NOT PRESENT.

## Critical distinction before using this file

A depeg is NOT automatically evidence of a security failure. The apxUSD/MIM case is the reference negative result: a stablecoin trading under $1 because its collateral legitimately repriced in a transparent, solvent market move is a different risk category entirely from a depeg caused by an unbacked mint. Conflating these two would be a real methodology error — scoring a protocol that behaved exactly as designed under stress the same way as one that was drained. Always determine *why* a depeg happened (mechanism failure vs. market-driven repricing) before applying either pattern below.

## Pattern 1: Mint Authority Control Risk

**What to check:** whether token minting is controlled by a privileged, often off-chain, key or service — and whether on-chain caps, collateral-ratio enforcement, or multi-party authorization exist as a check on that authority.

**Why this matters — real cases:**
- USR (Resolv Labs), March 2026: an attacker gained access to a privileged key tied to USR's minting mechanism — an off-chain service determining how many tokens could be minted on collateral deposit. The attacker deposited ~$200,000 in USDC, used the compromised key to mint ~80 million unbacked USR, and sold them on DEXs. There were no caps, no collateral ratios, and no on-chain safeguards — whoever controlled the key controlled the entire monetary supply.
- StablR, May 2026, $13.5M: the same attack class — a compromised governance/minting key — recurred two months later at a different protocol, confirming this is a repeatable pattern category, not a one-off.

**How to check:**
- Identify what authorizes a mint event: is it purely an on-chain function requiring deposited collateral in a fixed ratio, or does it depend on an off-chain service/oracle/privileged signer determining mint amounts?
- Check for an on-chain cap on total mintable supply relative to verified collateral.
- Check whether minting authority requires multiple independent signers/approvals, or a single key/service.

**Match criteria:**
- EXACT MATCH: minting is gated by a single off-chain key or service with no on-chain cap, no enforced collateral ratio, and no multi-party requirement.
- SIMILAR MATCH: some controls exist (e.g., a cap, or multi-sig) but key custody practices or threshold details are undisclosed.
- NOT PRESENT: minting is enforced purely by on-chain logic tied to verified collateral deposits, with no privileged off-chain override capability, or any override requires a disclosed, sufficiently-distributed multi-party process.

**What a genuine NOT PRESENT looks like (concrete example):** Ethena's USDe mint/redeem contract enforces a block-by-block minting cap, a price-divergence check that blocks mint/redeem if USDe's price diverges adversely from its backing stablecoins beyond a defined limit, and a strict on-chain whitelist of supported assets and custodian addresses. The combination is explicitly designed so that even a full compromise of the minting contract's private keys cannot, on its own, produce protocol losses under the stablecoin-only configuration — a meaningfully stronger and more specific claim than generic "secure minting" language, and the kind of concrete, contract-level evidence that should clear NOT PRESENT.

## Pattern 2: Collateral Liquidity Depth Risk

**What to check:** whether the stablecoin's backing collateral has sufficient, non-fragmented on-chain liquidity relative to the outstanding supply — distinct from collateral *quality* or solvency.

**Why this matters — real case (and why it must be read carefully):**
- The apxUSD/MIM case (June 2026) shows a stablecoin can depeg from thin, fragmented liquidity even when fully solvent. MIM's collateral was marked down in a selloff into thin, fragmented liquidity (~$35M spread across 47 pools, with pool-balance health around 12%) — there was no deep market to absorb the move, even though no collateral actually vanished. apxUSD's collateral simply repriced under market stress and the stablecoin did exactly what its design says it will do.
- This is NOT the same risk as Pattern 1. No key was compromised, no unauthorized mint occurred. The lesson is that a price feed or a simple "is this near $1" check cannot tell apart a solvent repricing from dead liquidity from an actual exploit — reading a depeg correctly requires looking at the collateral and the order book, not just the distance from a dollar.

**How to check:**
- Find total on-chain liquidity for the collateral backing the stablecoin, and how fragmented it is (number of pools, depth per pool).
- Compare liquidity depth to outstanding stablecoin supply — a large supply backed by thin, fragmented liquidity is a structural fragility even absent any attack.

**Match criteria:**
- EXACT MATCH: collateral liquidity is both thin (low absolute depth) and fragmented (spread across many small pools) relative to outstanding supply, with no documented redemption mechanism that doesn't depend on that fragmented liquidity.
- SIMILAR MATCH: liquidity data is partially available or a redemption mechanism exists but its capacity under stress is undisclosed.
- NOT PRESENT: collateral liquidity is deep and consolidated relative to outstanding supply, or a verified, non-market-dependent redemption mechanism exists (e.g., direct redemption against a custodied reserve).

**Important: a finding under Pattern 2 should never be described using exploit language ("hack," "drain," "compromised").** It describes a structural fragility, not a security breach — use language like "liquidity risk" or "redemption risk," consistent with what actually happened in the validating case.

## Pattern 3 (distinct risk dimension, for synthetic/derivative-backed stablecoins): Off-Chain Operational/Counterparty Dependency Risk

**What to check:** for stablecoins backed not by simple on-chain collateral but by an ongoing operational strategy (e.g., a delta-neutral hedge requiring continuous off-chain position management, custody, and exchange counterparty relationships), whether the peg's stability depends on operational processes that could fail independently of both mint-authority controls (Pattern 1) and on-chain collateral liquidity (Pattern 2).

**Why this is a distinct pattern, not a duplicate of Patterns 1 or 2:** a synthetic dollar can have a perfectly capped, multi-party-controlled mint function (passing Pattern 1) and deep, healthy on-chain liquidity (passing Pattern 2) while still carrying real risk through its backing *strategy* — custodian failure, derivatives exchange insolvency, a regulatory action freezing redemption, or a sustained adverse funding-rate environment depleting a reserve fund. Ethena's USDe is the clearest example: its peg depends on continuously maintained short perpetual futures positions across centralized exchanges, with collateral held by off-exchange settlement custodians — a real, ongoing operational dependency chain that exists alongside, not instead of, its on-chain mint controls.

**First real case validating EXACT MATCH criteria:** USDX (Stables Labs, November 2025) fell over 55%, trading below $0.45, when the Balancer V2 exploit (see dex-amm.md's out-of-scope section — a code-logic bug, not a DEX/AMM structural finding) caused a liquidity crunch that forced USDX's delta-neutral hedging positions to unwind. Critically, this was not simply an external shock the strategy could not have prepared for: USDX's collateral portfolio had reportedly not been rebalanced in months and included concentrated exposure to volatile, low-liquidity altcoins — a documented, disclosed failure in the strategy's own risk management, not just bad luck from an unrelated exploit. This is the first realized loss event in this library tying a stablecoin's off-chain operational strategy directly to a peg failure, and it defines what EXACT MATCH looks like going forward: a realized, dated peg failure where the proximate cause is a documented deficiency in the strategy's own risk management (stale positions, concentrated/illiquid holdings, insufficient diversification) — not merely a market-wide volatility event the strategy was reasonably designed to withstand.

**How to check:**
- Identify whether the stablecoin's backing strategy requires active, ongoing off-chain management (hedging, rebalancing, custody relationships) rather than static collateral sitting in a vault.
- Check for disclosed counterparty diversification (multiple custodians/exchanges vs. concentration in one) and a disclosed reserve fund sized to absorb adverse scenarios (e.g., sustained negative funding rates).
- Check for any history of regulatory action or counterparty disruption affecting redemption — a freeze on direct redemption (even if secondary-market trading continued) is a real, dated event worth surfacing, not dismissing as resolved simply because trading continued elsewhere.

**Match criteria:**
- EXACT MATCH: a realized, dated peg failure has occurred where the proximate cause is a documented deficiency in the backing strategy's own risk management (e.g., stale/unrebalanced positions, concentrated or illiquid holdings, insufficient counterparty diversification) — not merely broad market volatility the strategy was reasonably designed to withstand.
- SIMILAR MATCH: backing strategy depends on active off-chain management with disclosed risk factors, but the reserve fund's adequacy or counterparty diversification is not independently verifiable, and no realized peg failure has occurred.
- NOT PRESENT: this pattern does not apply (simple on-chain-collateralized stablecoin with no off-chain operational dependency), or a synthetic/strategy-backed stablecoin discloses verifiable counterparty diversification and a reserve fund with a stated, checkable sizing rationale.

**Related, separate concern worth surfacing even when not a formal pattern match:** cross-protocol concentration — if a large share of a stablecoin's total supply is concentrated as collateral or locked liquidity within one or two other major protocols (e.g., a yield-trading protocol holding the majority of a stablecoin's circulating supply), that concentration is a real systemic risk worth noting in any output, even though it does not yet have defined match criteria here.

## What this file does NOT cover

- General stablecoin peg mechanism design debates (algorithmic vs. collateralized vs. hybrid) — a design philosophy question, not a pattern-matchable vulnerability on its own.
- Deployment-sequence front-running, where an attacker races a protocol's own deployment transaction to claim a privileged admin role before the deployment script itself can (one real case found: USPD, December 2025, ~$1M — during deployment, an attacker executed a Multicall3 transaction that claimed an administrator role ahead of the protocol's own deployment script, then deployed a malicious proxy that forwarded ordinary calls through to the legitimate, audited logic — making the contract appear entirely normal to users and even to on-chain observers — while retaining the hijacked admin role. The attacker waited approximately three months as the protocol grew in value before exercising that control to mint roughly 98 million fake USPD and drain about $1M in real stETH. Notably, the underlying smart contract logic itself was confirmed audited and free of the vulnerability that was exploited — this was purely a deployment-sequencing gap, not a code flaw, meaning a standard code audit would not have caught it, but a check on deployment procedure could have). This is a genuinely distinct mechanism from every pattern above — not mint authority once live (Pattern 1), not collateral depth (Pattern 2), not off-chain counterparty risk (Pattern 3). Currently a single incident; not yet promotable to a scored pattern under the two-incident rule. **How to check:** for any protocol still in or near its deployment phase, verify whether the deployment script's admin-role-claiming transaction is protected against front-running (e.g., executed atomically within the same transaction as contract creation, using a deterministic deployment pattern like CREATE2 with a pre-committed admin address, rather than a separate, raceable transaction after deployment).
