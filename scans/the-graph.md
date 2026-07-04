# The Graph — DFJ Pattern Check

**Protocol:** The Graph (GRT) — indexing/staking protocol, Ethereum Mainnet + Arbitrum One
**Check type:** Post-deployment, live protocol
**Sources used:** Immunefi bug bounty scope page, `graphprotocol/contracts` GitHub repo (source code, `addresses.json`), four historical audit reports (ConsenSys Diligence ×3, Trust Security ×1) spanning May 2021–Feb 2023, and direct on-chain reads (Etherscan/Arbiscan) against Governor, Arbitrator, Controller, and BridgeEscrow contracts on both chains.

**Operating status:** Live, operating normally. No shutdown, wind-down, or active-incident status found.

**Category fit:** The Graph doesn't map cleanly to this library's 8 categories (it's an indexer-staking-and-arbitration protocol, a gap this library has never claimed to cover). Two pieces of scope map to an existing file (Bridge), and two cross-cutting checks (Concentrated Control Risk, Per-Chain Consistency) apply protocol-wide. All findings below are backed by direct on-chain lookups and primary-source contract reads — not inference from documentation.

---

## Technical Findings

**1. Bridge — BridgeEscrow ($52.7M)**
Pattern: Verifier/Validator Independence (bridge.md Pattern 1) → **NOT APPLICABLE** — confirmed via direct source read that `BridgeEscrow.sol` (41 lines) has no verifier/DVN logic at all; it's a pure GRT escrow relying on Arbitrum's canonical L1↔L2 bridge, not a custom third-party message-passing bridge. Applying this pattern would be a category error.

Pattern: Key Custody (bridge.md Pattern 3) → **SIMILAR MATCH, reframed as inherited/concentrated risk.** The contract's only two functions, `approveAll`/`revokeAll`, grant or revoke *unlimited* (`type(uint256).max`) GRT spending approval to any address, gated solely by `onlyGovernor`. There is no bridge-specific security layer, cap, or delay — the entire $52.7M has exactly one line of defense: the Governor Safe. Access control itself was verified clean (`Managed.sol`: `require(msg.sender == controller.getGovernor())`, no bypass found; upgrade path gated cleanly via `onlyProxyAdmin`). Evidence: `BridgeEscrow.sol` lines 30-40, `Managed.sol` lines 100-101, `GraphUpgradeable.sol` lines 26-37.

**2. Concentrated Control Risk — Governor**
**SIMILAR MATCH, trending toward NOT PRESENT.** Gnosis Safe, **6-of-11** threshold, confirmed via on-chain `governor()` read (selector `0x0c340a24`) against Controller on both chains. Signer set is **identical across Ethereum L1 and Arbitrum L2** (11/11 match). No overlap with the Arbitrator's signers. No Safe module (delay/timelock) attached — confirmed via Safe UI. This is a meaningfully more resistant setup than the patterns this library usually flags (KelpDAO's 1-of-1, Frax's 3-of-5 same-team multisig). What keeps it from a clean NOT PRESENT: full real-world independence of all 11 signers wasn't exhaustively verified (one resolves to `chris.eth` via ENS; the other 10 remain unidentified individuals/entities), and there is no timelock — once 6 signers act, execution is instant with no cooldown window for users to react.

**3. Concentrated Control Risk — Arbitrator (DisputeManager)**
**EXACT MATCH.** Gnosis Safe, **2-of-3 on Ethereum L1**, **2-of-4 on Arbitrum L2** — different signer sets (only one address shared between the two). Controls acceptance/rejection of query and indexing disputes, directly gating whether staked GRT gets slashed. The March 2022 ConsenSys audit independently confirms this is by design: *"disputes can only be accepted, rejected or drawn by the arbitrator role that can be delegated to a EOA or DAO"* — a *"semi-manual role"* with *"no guarantee that disputer's funds are ever released."* No timelock found on either chain's Arbitrator Safe. On both chains, only **2 signers** — a small, fixed, disclosed number — are needed to unilaterally decide slashing outcomes, with no meaningful friction. This is the strongest, most concrete finding of the entire scan.

**4. Per-Chain Consistency (Ethereum ↔ Arbitrum)**
- Governor: **NOT PRESENT** for inconsistency — confirmed identical signer set on both chains.
- Arbitrator: **EXACT MATCH** for inconsistency — confirmed materially different signer composition (3 vs. 4 signers, only 1 overlapping) despite identical product naming. The body that decides indexer slashing outcomes genuinely differs depending on which chain the dispute is filed on.

**5. GNS signal-splitting fund-theft lead (from Dec 2021 ConsenSys audit, re: PR-526)**
**NOT PRESENT — confirmed via direct source read, not inference.** The 2021 audit flagged a *different* PR's design (splitting curator signal in half between two deployments) as having "a flawed mathematical assumption" an attacker "could exploit to steal funds," never resolved in the four audit documents reviewed. Direct read of the current, live `GNS.sol::publishNewVersion()` (lines 301-354) shows a structurally different, simpler mechanism: burn 100% of old-deployment signal, remint 100% into the new deployment, holding `nSignal` constant. This does not match the flawed design — PR-526's approach appears to have been abandoned before shipping. The current function's own "(w/no slippage protection)" comments were separately checked for a reentrancy path: `Curation.sol::mint()`/`burn()` (lines 172-267) make only plain GRT ERC-20 `transfer`/`transferFrom` calls, and GRT has no transfer hooks (unlike ERC-777) — no reentrancy vector exists here.

**6. Known/acknowledged findings from the four audits reviewed — excluded from fresh submission**

| Finding | Status | Basis for exclusion |
|---|---|---|
| DisputeManager replay-protection removal (PR-548) | "Works as Designed," client-accepted | Known + acknowledged |
| Operator query-fee spoofing in Cobb-Douglas rebate pool (TRST-M-1) | Acknowledged, Open, called "acceptable consequence" | Known + accepted risk |
| Indexing-dispute front-running (2021 informal notes) | Never formally tracked | Frontrunning named out-of-scope by Immunefi regardless of audit history |
| `collect()` fully burns funds as tax if tx lands late (TRST-L-1) | Acknowledged, not fixed (interface not upgradable) | Known + accepted |

A materially different variant of any of these (different impact class or scale than what was assessed) could still be worth raising to the program directly rather than self-excluding — that judgment call belongs to the program, not this check.

**7. Out of this library's validated scope, not scored:** Curation/GNS bonding curves (no validated curation-specific pattern exists in this library — dex-amm.md covers swap pools, not signal-weighting curves); GraphToken, BillingConnector, GraphTokenLockWallet (no applicable pattern file).

---

## Breakdown (plain language)

This turned into a real, evidence-backed scan rather than a documentation-only check — most of what's below was confirmed by directly reading live contract code and on-chain data, not by trusting what the project says about itself.

- **Moving GRT between Ethereum and Arbitrum:** the $52.7M held in the bridge escrow isn't protected by a separate cross-chain security system the way some of the largest bridge hacks in this library were (KelpDAO, Ronin) — it's protected by exactly one thing: a group of people (see below) who can approve any address to spend the entire balance. That's not unusual for this kind of setup, but it does mean this pool of funds is only as safe as that one group.
- **Who can change the rules (the *Governor*):** a group of 11 people, 6 of whom must agree to act, controls the central registry every other contract in the system answers to — and the same 11 people control this on both Ethereum and Arbitrum. That's a notably larger, more distributed group than several protocols this library has flagged for concentrated control, though we couldn't fully confirm all 11 are genuinely unrelated individuals, and there's no cooling-off period once they act.
- **Who decides if you get slashed (the *Arbitrator*):** when an indexer is accused of misbehaving, a much smaller group — just 3 people on Ethereum, 4 on Arbitrum, with only 2 needed either way — decides the outcome, and it's largely a *different* set of people on each chain. This is the clearest finding in the whole check: a small, known number of signers can unilaterally decide whether someone's staked tokens get taken away, with no waiting period.
- **The one old, unresolved audit lead:** a 2021 review flagged that an earlier design for moving "subgraph" ownership between versions had a math flaw that could let someone steal funds. We checked the actual code running today, and it uses a different, simpler design than what was flagged — so this specific old warning does not describe what's currently live.
- **A few issues the project already knows about:** the audits turned up some real, previously-identified issues (like a way for a network operator to make a small profit by faking activity) that the team has already acknowledged and decided to accept rather than fix — these don't count as fresh discoveries.
- **Scope limit, stated plainly:** this only checks for a specific list of problems that have caused real losses elsewhere before, plus whatever was directly verified on-chain in this session. It found real, concrete answers on governance and arbitration structure that most checks like this never get past "undisclosed" on — but it still can't catch a brand-new kind of bug nobody has looked for, and nothing here should be read as either "risky" or "safe" as a blanket verdict.

---

## Still open (for future work)

Full real-world identity/independence of all Governor and Arbitrator signers beyond address-overlap checks; a line-by-line review of `L1GraphTokenGateway.sol` (497 lines — the message-handling side of the bridge, separate from BridgeEscrow's custody role); and `Curation.sol`/`RewardsManager.sol` beyond the specific functions checked here.
