# Lending Pattern Library

Validated against: Aave/KelpDAO rsETH exploit ($292M, April 2026), Cream Finance AMP listing ($34M, August 2021), Cream Finance yUSD vault exploit ($130M+, October 2021), Radiant Capital flash loan donation attack ($4.5M, Jan 2024 — exact match on Pattern 2), Centrifuge private credit pools (real defaults: Harbor Trade Credit and ConsolFreight CF4, 2023 — exact match on the RWA-equivalent NAV/custody risk pattern, see rwa.md). Confirmed out-of-scope case: Euler Finance ($197M, 2023) — pure code-logic bug, missed by 6 audits, belongs in Universal Core audit-weight logic, not here. Dry-run tested across Morpho Blue and Silo (isolated-market architecture, EVM), Solend (Solana — validated Pattern 2 cleanly, surfaced Concentrated Control Risk via SLND1), JustLend (Tron, EVM-compatible — no translation needed), Mars Protocol (Cosmos — confirmed, frozen/incident-response status correctly flagged).

## Global evidence-quality standard (applies to every pattern below)

A clean NOT PRESENT requires a specific, named, independently-checkable fact — actual on-chain collateral composition data, a named oracle provider with disclosed configuration, a documented isolation-mode/cap setting. Vendor language ("robust risk management," "carefully vetted collateral," "industry-leading risk framework") is never sufficient. When only this kind of language is available, output SIMILAR MATCH with a note that primary-source (on-chain or governance-forum) verification is needed.

## Before applying any pattern below: check protocol architecture

Not every lending protocol has a single, shared collateral pool. Some (e.g., Morpho Blue, and similar permissionless market-creation frameworks) let anyone deploy isolated markets, each with its own independently-chosen collateral asset, oracle, and risk parameters — and risk in one market cannot spread to another by design. For this architecture type:
- Pattern 1 (Collateral Concentration) must be applied **per individual market**, not as a protocol-wide aggregate. A statement like "Protocol X is 40% concentrated in Asset Y" is meaningless if X is actually 180 independent markets — instead, identify and score the specific market in question.
- If the user's request is about "the protocol" generally rather than a named market, say so explicitly and ask which market, or note that a protocol-wide score is not meaningful for this architecture type rather than producing a falsely aggregated number.
- For single-pool protocols (e.g., Aave, Compound), Pattern 1 applies at the protocol level as originally designed below.

## Pattern 1: Collateral Concentration in Cross-Chain-Dependent Assets

**What to check:** what percentage of the protocol's total collateral base is composed of a single non-stablecoin asset, and whether that asset's backing depends on a cross-chain bridge the lending protocol itself does not control.

**Why this matters — real case:**
- Aave accepted rsETH (KelpDAO's liquid restaking token) as collateral, with concentrated e-mode leverage. rsETH's backing depended on a LayerZero bridge route configured as 1-of-1 (see `bridge.md` Pattern 1). When that bridge was exploited, 116,500 unbacked rsETH entered circulation and was used as collateral on Aave — Aave's own contracts were never touched, but it absorbed $6.6B in TVL impact and $123.7M-$230.1M in bad debt.

**How to check:**
- Pull on-chain collateral composition (subgraph query, DeFiLlama, or the protocol's own risk dashboard if published).
- Flag any single non-stablecoin asset representing >25% of total collateral value.
- For any flagged asset, trace its backing mechanism — is it a liquid staking/restaking token, a bridged/wrapped asset? If yes, check that asset's own dependency chain against `bridge.md`.

**Match criteria:**
- EXACT MATCH: a cross-chain-dependent asset (LST, LRT, wrapped token) represents >25% of collateral AND its backing bridge has an unresolved Bridge-category EXACT MATCH finding.
- SIMILAR MATCH: concentration exists but the underlying bridge dependency is undisclosed or unverified.
- NOT PRESENT: collateral base is diversified (no single non-stablecoin asset >25%) or concentrated assets have verified, independently-secured backing.

## Pattern 2: Exotic/Non-Standard Token Integration Risk

**What to check:** whether any listed collateral asset uses a non-standard token implementation with transfer hooks, callbacks, or donation-manipulable accounting — properties that can be weaponized even though the token "works as designed." *(Note: the specific standards named below — ERC-777, ERC-20 — are Ethereum/EVM-specific. On other chains, check for the equivalent concept using that chain's actual token standard: e.g., a Solana SPL token with a non-standard transfer hook extension, or a Move-based token with custom transfer logic. The underlying risk — a token whose transfer behavior does something unexpected beyond a simple balance change — applies on any chain; the specific standard name does not.)*

**Why this matters — real case:**
- Cream Finance listed AMP, an ERC-777 token, as collateral on Feb 10, 2021. ERC-777's transfer-callback feature created a reentrancy surface that didn't exist in standard ERC-20 tokens. The token worked exactly as designed — the risk was Cream's choice to accept it as collateral without accounting for that design difference. Exploited for $34M six months after listing.
- Separately, Cream's October 2021 exploit ($130M+) involved a Yearn vault token (crYUSD) whose exchange rate could be manipulated by donating assets directly to the underlying vault — a donation-manipulable share-price pattern, distinct from the ERC-777 issue but same root category: accepting a collateral asset whose accounting can be externally manipulated.

**How to check:**
- For each collateral asset, check the token standard. Flag any non-standard implementation (ERC-777, rebasing tokens, tokens with transfer fees/hooks).
- Check whether any collateral asset's exchange rate or share price is calculated from a pool/vault balance that can be altered by direct donation (i.e., sending tokens to the contract without going through the official deposit function).

**Match criteria:**
- EXACT MATCH: collateral asset uses ERC-777 or equivalent callback-enabled standard with no documented mitigation, OR exchange rate is calculated from a directly-donatable balance.
- SIMILAR MATCH: non-standard token present but documented mitigations exist (e.g., reentrancy guards, donation-resistant accounting) — verify mitigation is real, not just claimed.
- NOT PRESENT: all collateral assets are standard ERC-20 with accounting derived from internally-tracked balances, not raw `balanceOf()` reads.

## Pattern 3 (lower confidence, mechanism-described but not yet incident-validated): Curator/Allocator Risk

**What to check:** for vault-based or curated lending products (where a third party decides which underlying markets a depositor's funds flow into, rather than the depositor choosing a specific market directly), whether the curator's allocation strategy and track record are transparent and verifiable.

**Why this is flagged at lower confidence:** this risk is real and well-described by the industry — a curator can allocate depositor funds to risky, thinly-collateralized, or poorly-oracled markets, and depositors relying on a vault interface may not realize the underlying risk has shifted. However, this conversation has not yet validated this pattern against a specific, named, dated loss incident the way Patterns 1 and 2 are validated. Treat any finding here as a SIMILAR MATCH / watch-item at most, not an EXACT MATCH, until a real case is identified.

**How to check:**
- Identify whether the product in question is a direct market position (depositor chooses the specific market) or a curated vault (a third party allocates across markets on the depositor's behalf).
- For curated vaults, check whether the curator publishes allocation strategy, track record, and the specific underlying markets currently in use.
- Cross-check the underlying markets a vault allocates to against Patterns 1 and 2 above — curator risk often manifests as "good vault interface, risky underlying markets," so the underlying market check still matters even when a curator layer exists.

**Match criteria:**
- SIMILAR MATCH (ceiling for this pattern currently): curator allocations are opaque, undisclosed, or the underlying markets fail Pattern 1/2 checks.
- NOT PRESENT: curator publishes transparent, verifiable allocation strategy and underlying markets independently pass Pattern 1/2 checks.

## Concentrated Control Risk (cross-cutting — see SKILL.md)

The question "how many independent parties have to collude to take a severe, unilateral action" is no longer a lending-specific pattern. It generalized across lending governance (Solend's SLND1 fund-seizure vote), bridge admin multisigs (Frax's 3-of-5 team control), and base-layer validator/consensus concentration (Hyperliquid's core-contributor token concentration) — the same underlying question, appearing at different layers. This check now lives as a cross-cutting rule in SKILL.md, applied alongside whichever category-specific file(s) are in use, rather than being a lending-only pattern. See SKILL.md's "Concentrated Control Risk" section for the full check; Solend's SLND1 incident remains the validating case.

## What this file does NOT cover

- Pure code-logic bugs unrelated to collateral choice (missing health checks, arithmetic errors in liquidation math) — these are Universal Core / audit-weight issues. The Euler Finance case (missing insolvency check in `donateToReserves`) is the reference negative result: six professional audits missed it, and no collateral-listing decision would have caught it either, because the flaw was in Euler's own code, not in what it chose to accept.
- Interest rate model design and liquidation incentive tuning — these are economic design choices, not pattern-matchable security risks in the same sense.
