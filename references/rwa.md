# RWA (Real-World Asset) Pattern Library

Validated against: Zoth RWA restaking exploit ($8.5M, March 21, 2025 — compromised private key, "classic operational security failure"); a $1.78M oracle misconfiguration on a Base-deployed lending protocol (February 2026) involving an RWA-adjacent collateral asset; Centrifuge private credit pools (EXACT MATCH on Pattern 2 — single price-admin key submits off-chain-calculated NAV with no independent on-chain verification; real, dated defaults at Harbor Trade Credit Series 2 and ConsolFreight CF4, both 2023, where on-chain NAV did not reflect impaired off-chain assets until governance intervention, blocking investor redemptions). Industry context: RWA-specific exploit losses reached $14.6M in H1 2025 alone, more than double full-year 2024 losses, defined by CertiK as "entirely onchain and operational failures" — marking a transformation in the RWA threat landscape.

## Why RWA needs its own file, not just a Stablecoin sub-pattern

An RWA token's value is a claim on an off-chain asset — this expands the attack surface beyond smart contracts into a five-layer hybrid stack: the underlying real-world asset itself, the legal/custodial structure holding it, the attestation/oracle layer reporting its value or existence, the smart contract layer, and the secondary market layer. Stablecoin Pattern 3 (Off-Chain Operational/Counterparty Dependency Risk) covers synthetic/derivative-backed stablecoins specifically. This file covers the broader RWA category — tokenized treasuries, private credit, commodities, real estate, and similar — where the core risk is not a hedging strategy but a legal and custodial claim on a physical or contractual asset.

## Global evidence-quality standard

A clean NOT PRESENT requires a specific, named, independently-checkable fact — a disclosed custodian with regulatory registration, a verifiable proof-of-reserves attestation mechanism, documented key custody practices for any privileged operational role. Vendor language ("institutional-grade custody," "fully backed," "regulated and compliant") is never sufficient on its own. When only this kind of language is available, output SIMILAR MATCH with a note that primary-source verification is needed.

## Pattern 1: Off-Chain Custody/Operational Key Risk

**What to check:** who holds operational control over the off-chain asset or the on-chain representation's privileged functions (minting, redemption approval, attestation submission), and what key custody practices protect that control.

**Why this matters — real case:**
- Zoth, an RWA restaking protocol, lost $8.5M on March 21, 2025 to what CertiK characterized as "a classic operational security failure" — a compromised private key. This is structurally the same failure mode validated in `stablecoin.md` Pattern 1 (USR, StablR) and `bridge.md` Pattern 3 (IoTeX, Multichain), but applied here to the specific operational role of managing an RWA's off-chain/on-chain bridge of control. The recurrence of this exact failure mode across stablecoins, bridges, and now RWA protocols suggests privileged-key compromise is a cross-category risk that should always be checked regardless of protocol type, not a category-specific quirk.

**How to check:**
- Identify every privileged role that can mint, burn, redeem, or attest to backing for the RWA token.
- Check whether each role is a single key/EOA or a disclosed multi-party/HSM-backed mechanism.
- Check whether the underlying real-world custodian (a bank, transfer agent, fund administrator) is named and independently verifiable (e.g., SEC registration, regulatory filing) as distinct from the on-chain operator.

**Match criteria:**
- EXACT MATCH: a single key or undisclosed-custody role controls minting/redemption/attestation with no multi-party requirement.
- SIMILAR MATCH: multi-party controls exist but custody practices (HSM, geographic distribution) are undisclosed, or the off-chain custodian's regulatory status is unverified.
- NOT PRESENT: privileged roles are multi-party controlled with disclosed custody practices, AND the off-chain custodian is independently verifiable (e.g., a named, regulated transfer agent or fund administrator).

## Pattern 2: Oracle/Proof-of-Reserves Integrity Risk

**What to check:** how the protocol attests that the off-chain asset backing the token actually exists and is correctly valued, and what happens when that attestation is wrong or delayed.

**Why this matters — real case:**
- A DeFi lending protocol lost $1.78M in February 2026 when a governance proposal misconfigured an oracle wrapper on a Base deployment — the oracle used only the raw exchange rate between two assets instead of multiplying it by the correct USD price, mispricing the asset by 99.95%. Critically, monitoring systems detected the discrepancy within minutes, but the governance timelock required a five-day voting period to correct it, during which liquidations continued on the bad price — the protocol's own safety mechanism (the timelock) became the vehicle that prolonged the loss. This is structurally similar to the governance-stall pattern validated in `yield-aggregator.md` Pattern 1 (Yearn), but applied to oracle correction rather than strategy retirement.
- Oracle manipulation/misconfiguration is described by industry security researchers as the single most commonly exploited vulnerability in RWA-adjacent protocols specifically.

**How to check:**
- Identify how the protocol's oracle or attestation mechanism is constructed — does it correctly compose multiple price/value legs (e.g., asset:asset rate × asset:USD rate), or could a single-leg misconfiguration silently produce a severely wrong value?
- Check whether the protocol has a circuit breaker that halts operations on extreme price deviation, independent of any governance timelock.
- Check whether a proof-of-reserves mechanism exists for the underlying asset, and whether it is independently verifiable (e.g., a named third-party attestor) rather than self-reported by the issuer.
- If a timelock or governance delay exists for correcting oracle parameters, check whether emergency/pause mechanisms can act faster than the standard governance path during an active pricing failure — a safety mechanism that cannot be bypassed in an emergency is itself a finding.

**Match criteria:**
- EXACT MATCH: the oracle/attestation construction has a verifiable composition error, or no circuit breaker exists for extreme deviation, and any correction path is gated by a multi-day governance process with no faster emergency override.
- SIMILAR MATCH: a circuit breaker or proof-of-reserves mechanism exists but its independence (third-party vs. self-attested) or responsiveness under stress is unverified.
- NOT PRESENT: oracle composition is verified correct, a circuit breaker independent of governance timelock exists, and proof-of-reserves is independently, verifiably attested.

## What this file does NOT cover

- Legal enforceability of the underlying claim (whether a token holder's on-chain claim would actually hold up in bankruptcy or a legal dispute over the real-world asset) — this is a legal/regulatory question outside the scope of pattern-matching against code or on-chain configuration. Flag as a known, disclosed risk category when relevant, but do not attempt to assign a match rating to legal enforceability itself.
- Business/market risk of the underlying asset class (e.g., real estate market downturns, credit defaults in tokenized private credit) — this is investment risk, not a security pattern.
