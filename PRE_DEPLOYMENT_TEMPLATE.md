# DFJ Pre-Deployment Design Review Template

**Version 1.0**
**Fill this in before writing code. Run it through the DFJ-Pattern-checker before your first design review.**

---

## Instructions

Answer every question you can answer. Leave blank what you genuinely do not know yet — blank answers are findings, not failures. The checker will flag them as CANNOT DETERMINE, which is honest and useful before deployment rather than embarrassing after.

The goal is not to pass a checklist. The goal is to surface the structural decisions that have already cost the industry money, before you make them.

---

## Section 1: Protocol Identity

**Protocol name:**

**Primary category:** (choose one)
- [ ] Lending
- [ ] DEX / AMM
- [ ] Bridge
- [ ] Derivatives / Perpetuals
- [ ] Stablecoin / CDP
- [ ] Yield Aggregator
- [ ] RWA (Real-World Asset)
- [ ] Insurance

**Chains planned for deployment:**

**Estimated launch date:**

**Brief description of what the protocol does (2–3 sentences):**

---

## Section 2: Lending Protocols

*Skip if not applicable.*

**What assets will users be able to deposit as collateral?**

**For each collateral asset, is it:**
- Natively issued on this chain, or bridged from another chain?
- If bridged: what bridge mechanism carries it? Who are the verifiers?
- Does its price depend on an external protocol's solvency or liquidity?

**What oracle(s) will you use to price collateral?**
- Single source or aggregated across multiple independent sources?
- Is the price derived from an instantaneous spot read or a time-weighted average?
- What happens if the oracle returns an obviously wrong price?

**Is this a direct lending market or a curated vault model?**
- If curated: who are the curators, what is their mandate, and what allocation decisions can they make unilaterally?
- If curated: what happens to depositor funds if a curator makes a bad allocation decision?

---

## Section 3: DEX / AMM Protocols

*Skip if not applicable.*

**What mechanism determines asset prices within the protocol?**
- Instantaneous reserve ratio only?
- Time-weighted average price (TWAP)?
- External oracle?

**Can the price be moved significantly within a single transaction?**
- If yes: is there any mechanism preventing that price from being used as an input to another action in the same transaction?

**Are there any auxiliary mechanisms (fees, burns, rebasing) that could affect the pool ratio independently of actual trades?**

---

## Section 4: Bridge Protocols

*Skip if not applicable.*

**How does the bridge verify that an event happened on the source chain?**
- Who are the verifiers / validators?
- How many independent verifiers are required to confirm a transfer?
- Are the verifiers genuinely independent entities, or the same team under different names?

**What happens if one verifier goes offline or is compromised?**
- Is there a documented failover process?
- Has the failover ever been tested?

**Who holds the private keys that control bridge configuration?**
- Single key or multisig?
- If multisig: what is the threshold? Are all signers named and independent?
- Is there a timelock before configuration changes take effect?

**How are signers presented with transaction details before signing?**
- Do they see the raw calldata or a human-readable summary?
- Is the signing interface the team's own software or a third-party tool?

---

## Section 5: Stablecoin / CDP Protocols

*Skip if not applicable.*

**Who or what can mint new tokens?**
- Is mint authority held by a single key, a multisig, or an on-chain smart contract with enforced rules?
- If a single key: where is it stored? Hot wallet, cold wallet, HSM, cloud KMS?
- Is there an on-chain maximum mint limit per transaction, per epoch, or in total?

**What backs the value of the token?**
- On-chain assets, off-chain assets, or algorithmic?
- If off-chain: who custodies the backing assets, and how is the backing verified on-chain?
- If algorithmic: what happens to the peg if the collateral ratio drops below 1:1?

**What is the redemption mechanism?**
- Can users always redeem at par?
- Under what conditions is redemption paused or restricted?

**Is any part of the backing managed by an external party off-chain?**
- If yes: what oversight exists over their decisions?
- Is there an independent proof of reserves?

---

## Section 6: Derivatives / Perpetuals Protocols

*Skip if not applicable.*

**What is the maximum leverage available to users?**

**What is the total liquidity available to cover losing positions?**
- Insurance fund size?
- Vault depth relative to maximum open interest?

**What oracle determines the mark price used for liquidations?**
- Single exchange feed or aggregated across multiple independent sources?
- What is the maximum price deviation that triggers an error / pauses the system?

**Does the protocol offer any binary or prediction-style markets?**
- Markets that settle at a fixed extreme value (e.g., 0 or 1) based on a real-world outcome?
- If yes: what happens if there is not enough capital on the losing side to fully pay out the winning side?

---

## Section 7: Yield Aggregator Protocols

*Skip if not applicable.*

**What strategies will the protocol deploy depositor funds into?**
- List each strategy and the protocol it interacts with.

**Are any of these strategies in deprecated or legacy contracts?**
- Contracts that are no longer actively maintained or audited?

**How is the vault's share price calculated?**
- Does the calculation read the raw token balance of the vault contract?
- Can the share price be affected by someone sending tokens directly to the vault address without going through the deposit function?

---

## Section 7b: RWA (Real-World Asset) Protocols

*Skip if not applicable.*

**Who holds custody of the real-world assets backing the on-chain tokens?**
- Named custodian with independent verification, or the protocol team itself?
- Is the custody arrangement governed by a legal agreement visible to token holders?

**Who controls the private key or admin role that can update the on-chain NAV or asset valuation?**
- Single key or multisig?
- Is the NAV submitted by the same party that holds the assets — with no independent check?

**How is the real-world asset value verified on-chain?**
- Is there an independent proof of reserves, attestation, or oracle?
- How frequently is it updated?
- What happens if the on-chain value does not reflect a real-world default or impairment?

**Under what conditions can redemptions be paused or delayed?**
- Is this disclosed to users before they deposit?

---

## Section 7c: Insurance Protocols

*Skip if not applicable.*

**What is the total capital in the insurance pool?**
- How does this compare to the total value of risk underwritten?
- What is the maximum single claim the pool could pay without becoming insolvent?

**Who assesses and approves claims?**
- Token holders, a dedicated committee, or an automated system?
- Do the assessors have a financial stake in the outcome of their vote — i.e., does rejecting a claim benefit them directly?

**What prevents a small group of assessors from coordinating to reject valid claims?**
- Is there a quorum requirement?
- Is there an appeal mechanism?

**What happens if multiple large claims arrive simultaneously?**
- Is there a documented process for prioritisation or partial payment?

---

## Section 8: Governance and Admin Controls

*Answer for all protocol types.*

**What is the most powerful action an admin can take?**
(e.g., pause the protocol, upgrade contracts, change oracle, mint tokens, withdraw treasury)

**Who controls this action?**
- Single wallet / EOA?
- Multisig — if so, what threshold and how many signers?
- On-chain governance vote — if so, what quorum and what timelock?

**Is there a timelock before admin actions take effect?**
- If yes: how long?
- If no: why not?

**Has any admin action been exercised in a test or staging environment?**
- If yes: what was the outcome?

**Are all admin key holders genuinely independent of each other?**
- Or are they the same team / same legal entity under different names?

---

## Section 9: Supply Chain and Release Process

*Answer for all protocol types.*

**Who has the ability to push a change to the production frontend?**
- Single developer, or a multi-party review process?

**Are frontend dependencies (npm packages, third-party scripts) pinned to specific versions?**
- Or do they pull the latest version on each build?

**Is there an independent review of the build and deployment pipeline?**
- Or does the same person who writes the code also deploy it?

**Does the bug bounty program cover the frontend and infrastructure, or smart contracts only?**

---

## Section 10: Audit and Scope Coverage

*Answer for all protocol types.*

**List every contract or component that will hold or interact with user funds:**

**For each item above, confirm:**
- Will it be audited before deployment? By which firm?
- Will it be in scope for the bug bounty program?
- If not — why not, and what mitigates the risk of an unreviewed component?

**Are there any contracts from a previous version of this protocol that users will still be able to interact with after the new version launches?**
- If yes: are those legacy contracts in audit scope and bounty scope?

---

## Section 11: Multi-Chain Consistency

*Answer if deploying on more than one chain.*

**For each chain listed in Section 1, confirm whether the following are identical across all deployments or intentionally different:**

| Configuration | Chain A | Chain B | Chain C | Notes |
|---|---|---|---|---|
| Admin multisig threshold | | | | |
| Oracle source(s) | | | | |
| Bridge verifier set | | | | |
| Contract version / bytecode | | | | |
| Timelock duration | | | | |

**If any configuration differs across chains, explain why and what compensating control exists on the less-protected deployment.**

---

## How This Template Gets Checked

Submit this completed document to the DFJ-Pattern-checker instead of a live protocol name. The checker will:

1. Read your design decisions against the same pattern library used for live protocol scoring
2. Return findings for each relevant pattern — EXACT MATCH, SIMILAR MATCH, NOT PRESENT, or CANNOT DETERMINE
3. Flag blank answers as CANNOT DETERMINE — these are the decisions that need to be made before deployment, not after
4. Output a pre-deployment finding report, not a post-deployment score

**A finding before deployment is a decision. A finding after deployment is a loss.**

---

*DeFiJerusalem Pre-Deployment Design Review Template v1.0*
*github.com/Defijerusalem/DFJ-Pattern-checker*
