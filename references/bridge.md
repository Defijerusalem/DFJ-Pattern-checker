# Bridge Pattern Library

Validated against: KelpDAO ($292M, April 2026), Ronin ($625M, 2022), Wormhole ($320M, 2022), IoTeX ioTube ($4.4M, 2026), Multichain (2023, CEO-linked keys), Orbit Chain ($81.5M, Jan 2024, 7-of-10 keys compromised), CrossCurve ($3M, Jan 2026), Radiant Capital ($53M, Oct 2024 — signing-interface spoofing), Bybit ($1.4-1.5B, Feb 2025 — same mechanism as Radiant, independently confirmed), Secret Network/Axelar IBC bridge ($4.67M, June 2026 — disabled verification check, Cosmos-native). Also dry-run tested without new pattern gaps against Stargate, Pendle, Frax (LayerZero-based), and Wormhole/Axelar/Chainlink CCIP (architecturally distinct, non-LayerZero) — see "Industry-wide pattern" note under Pattern 3 below.

## Global evidence-quality standard (applies to every pattern below)

A clean NOT PRESENT determination requires a specific, named, independently-checkable fact (an on-chain signer list, a disclosed audit finding, a documented key-custody mechanism). General reassurance language from the protocol's own marketing, docs, or team — "robust," "battle-tested," "industry-leading security," "conservative configuration" — is never sufficient on its own. When only this kind of language is available, output SIMILAR MATCH with a note that primary-source verification is still needed, not NOT PRESENT. This rule exists because a dry run on Stargate showed the checker almost passed a real, scoreable risk category based on vendor description alone — treat that as the standard failure mode to actively guard against.

**Distinguish "undisclosed" from "requires an on-chain contract read."** For LayerZero-based protocols specifically, the actual DVN configuration (signer list, threshold) is a real, technically public on-chain value — but retrieving it requires calling `getConfig()` on the LayerZero Endpoint contract with the specific OApp's address, library address, and chain EID. This is a contract read, not a document search. Web search and documentation review will not surface it, no matter how many adjacent LayerZero pages are found, because the information lives in contract state, not in indexed text. When this specific verification is unavailable because the checker has no contract-call capability in the current session, say so explicitly — e.g., "this requires an on-chain `getConfig()` call against the OApp's address, which this check could not perform" — rather than presenting general LayerZero documentation as if it were progress toward an answer. This is a distinct situation from a protocol that genuinely never discloses its configuration anywhere, even on-chain (rare, but possible with proxy/upgradeable patterns) — note which situation applies when reporting SIMILAR MATCH for this reason, since the former has a clear, specific next step (a contract call) and the latter may not.


## Pattern 1: Verifier/Validator Independent-Operator Count

**What to check:** the number of signers/verifiers required to approve a cross-chain message, AND how many of those signers are genuinely independent entities (not the same team/company controlling multiple "independent" keys).

**Why this matters — real cases:**
- KelpDAO's LayerZero route used a 1-of-1 DVN (Decentralized Verifier Network) — a single verifier, no redundancy at all.
- Ronin required 5-of-9 signatures, which looks reasonably decentralized on paper — but 4 of the 5 compromised signers belonged to the same single entity (Sky Mavis). Raw threshold count was not the real protective factor; independent-operator count was.

**How to check:**
- Look for DVN, oracle network, or validator set configuration in the bridge contract or docs (e.g., LayerZero's `setConfig`, Axelar's validator set, custom multisig addresses).
- Count the signing threshold (M-of-N).
- Separately identify how many *distinct, named entities* control those N keys. If the docs/audit don't disclose this, flag as CANNOT DETERMINE rather than assuming independence.

**Match criteria:**
- EXACT MATCH (high risk): 1-of-1, or any threshold where a single entity controls a majority of signers.
- SIMILAR MATCH: M-of-N where N ≥ 3 but operator independence is undisclosed or unclear.
- NOT PRESENT: documented, independently-verified multi-entity signer set with threshold requiring collusion across organizations.

**Critical evidence-quality rule:** a vendor's own descriptive language ("conservative DVN set," "opinionated security stack," "carefully selected DVNs," "best-in-class security") is NOT sufficient evidence for a NOT PRESENT determination. These are marketing characterizations, not disclosed configurations. Only a named, on-chain-verifiable signer/DVN list (e.g., pulled from the actual `setConfig` call, a block explorer, or a tool like LayerZero Scan) counts as evidence. If only vendor prose is available, the correct output is SIMILAR MATCH with a note that primary-source verification is needed — never NOT PRESENT.

**LayerZero-specific check (apply by default to any LayerZero-based OApp, not just bridges that have already had an incident):** LayerZero's architecture shifts DVN security configuration responsibility to each individual application rather than enforcing a network-wide baseline. As of the KelpDAO incident analysis (April 2026), roughly 47% of active LayerZero OApp contracts were running a 1-of-1 DVN configuration, representing over $4.5 billion in associated exposure — this is a widespread structural pattern, not a rare misconfiguration. LayerZero's own bug bounty program explicitly excludes "impacts to OApps themselves as a result of their own misconfiguration," including verifier network choices — meaning the protocol layer does not backstop this risk. For any LayerZero-based protocol, always attempt to pull the actual configured DVN set for the specific token/pathway in question rather than treating "built on LayerZero" as informative on its own. "Built on LayerZero" says nothing about safety by itself — the application's own DVN choice is what matters, and that choice varies enormously across otherwise-similar-looking apps.

## Pattern 2: Failover/Degradation Behavior Under Stress

**What to check:** what happens when a bridge's primary verification path (e.g., an external RPC node, a primary oracle) becomes unreachable. Does it fail safe (pause) or fail open (route to a fallback path that could be attacker-influenced)?

**Why this matters — real case:**
- In the KelpDAO exploit, attackers DDoS'd an external RPC node the DVN relied on. With the external path unreachable, the DVN failed over to internal nodes — which the attackers had separately compromised. The failover mechanism itself became the attack surface.

**How to check:**
- Look for fallback/failover logic in bridge relayer or verifier configuration.
- Check whether failover requires the same trust assumptions as the primary path, or weaker ones.
- Check whether an unreachable primary path triggers a pause/halt instead of an automatic failover.

**Match criteria:**
- EXACT MATCH: failover automatically routes to a smaller or less-audited set of nodes/verifiers than the primary path.
- SIMILAR MATCH: failover behavior exists but is undocumented or unclear from available sources.
- NOT PRESENT: unreachable primary path triggers a pause/halt requiring manual, multi-party intervention to resume.

## Pattern 3: Key Custody Architecture

**What to check:** whether privileged operations (admin upgrades, withdrawal approval, validator key management) depend on a single private key versus distributed/HSM-backed/multi-party signing.

**Why this matters — real cases:**
- IoTeX's ioTube bridge relied on a single validator owner key for critical Ethereum-side contracts.
- Multichain's bridge failure was tied to CEO-linked keys.
- Orbit Chain lost $81.5M when 7 of its 10 multisig keys were compromised — note this is a HIGH threshold (7-of-10) that still failed, reinforcing that threshold count alone is not protective if key storage/distribution is weak.

**How to check:**
- Look for documentation of key storage (HSM, MPC, cold storage) versus a single hot wallet or admin EOA — on non-EVM chains, check the equivalent: is the privileged role a single standard keypair-controlled wallet with no other safeguard, or a multi-party/program-enforced mechanism (e.g., a Squads multisig on Solana, a Cosmos multi-signature account)?
- Check whether any single role (deployer, admin, CEO-linked address) can unilaterally execute privileged bridge functions, regardless of what that chain calls its account/wallet model.

**Match criteria:**
- EXACT MATCH: a single key, standard wallet, or hot-wallet-equivalent (the EVM term for this is an EOA — externally-owned account — but the same underlying risk exists under different names on every chain) controls privileged bridge functions with no time-lock or secondary approval.
- SIMILAR MATCH: multi-party key custody exists but storage/distribution practices are undisclosed.
- NOT PRESENT: documented HSM or MPC-based distributed key custody with no single point of compromise.

**Industry-wide pattern, not a single-protocol quirk:** as of this writing, Pattern 3 has not cleared to NOT PRESENT in any test run against this library — not LayerZero-based bridges (Stargate, Pendle, Frax), nor architecturally distinct protocols with otherwise strong, named, on-chain-verifiable Pattern 1/2 results (Wormhole, Axelar, Chainlink CCIP). Wormhole names 19 guardians publicly and still leaves per-guardian key storage practices undisclosed; Axelar's MPC threshold-signature design is structurally stronger than a per-signer EOA model and still leaves individual shard storage undisclosed; CCIP's dual-layer DON+RMN architecture is the most independently verified Pattern 1 result obtained so far and still relies on "rigorous private key management" marketing language for Pattern 3. Treat a SIMILAR MATCH on this pattern as the current honest ceiling for nearly any bridge checked, not a specific red flag against the protocol being scored relative to its peers — the absence of industry-wide disclosure standards here means this pattern is currently better at confirming the gap exists everywhere than at differentiating one bridge's practices from another's. If a protocol is ever found to publicly disclose HSM/MPC storage specifics at the individual-operator level, that would be a genuinely notable, score-worthy differentiator precisely because it would be the exception, not the norm.

## Pattern 4 (bonus, comparable metric): Detection/Response Time

**What to check:** historical or stated incident-response capability — specifically, the ability to pause/freeze the bridge quickly if anomalous activity is detected.

**Why this matters — real cases, for comparison:**
- Ronin: undetected for 5 days.
- KelpDAO: detected and paused after 46 minutes — too late to prevent the loss, but a meaningfully faster response than Ronin.
- IoTeX: detected within hours.

**How to check:**
- Look for a documented guardian/pause mechanism and whether it has been tested or used in a real incident.
- This is not a pass/fail check — record response time as a comparative data point if a past incident exists, or note "no incident history to evaluate" if the protocol has never been tested.

**Match criteria:** N/A — this is a comparative metric, not a binary match. Report response time if known; do not penalize a protocol for lacking incident history (no incident is not evidence of weakness).

## Pattern 5: Signing-Interface Spoofing (Display vs. Actual Transaction Mismatch)

**What to check:** whether the protocol's privileged signers (multisig holders, admin keys) rely on a software interface to review and approve transactions, and whether that interface's display can be manipulated to show something different from what is actually being signed.

**Why this matters — real cases (validated independently, twice, by the same attacker group):**
- Radiant Capital, October 2024 ($53M): the protocol had upgraded its security to a 4-of-7 multisig using hardware wallets (Ledger) — a setup that would normally clear most of this file's other patterns well. The attack (attributed to Lazarus Group) did not break the multisig threshold or compromise the hardware devices themselves. Instead, malware intercepted the Safe{Wallet} front-end interface that signers used to review transactions before approving them on their hardware wallets. Signers saw what appeared to be a legitimate, routine transaction on screen — the hardware wallet then faithfully signed the transaction it was actually sent, which was malicious. No documented fix for this specific vector existed before the protocol's eventual shutdown in June 2026.
- Bybit, February 2025 ($1.4–1.5B, the largest cryptocurrency theft on record): the same root mechanism, the same compromised software (Safe{Wallet}), the same attacker group (Lazarus Group/TraderTraitor), independently, at a different organization, four months later. Attackers compromised a Safe developer's environment and injected malicious JavaScript into the interface Bybit's signers used. The single most important technical detail: the malicious transaction changed the operation type to a delegatecall (a call type that can hand over control of the entire wallet's logic) instead of a normal transfer — and because delegatecall data has no human-readable format in a standard multisig UI, signers had no practical way to notice the difference even if they were being careful. The transaction otherwise looked identical to a routine transfer Bybit had performed before.
- This is now the strongest cross-validated pattern in this file: two independent, large, dollar-quantified losses, different organizations, same exact mechanism, confirming this is a real, repeatable, attacker-favored technique — not a one-off.

**Known mitigations, validated by post-incident analysis (useful for distinguishing a real NOT PRESENT from an untested claim):**
- Pre-signing transaction simulation, allowing signers to preview the actual effect/destination of a transaction before approving, independent of the primary UI's summary.
- Raw transaction data / calldata validation — reviewing the actual data sent to the smart contract rather than trusting the interface's human-readable summary, with particular attention to the operation type (a standard transfer/call vs. a delegatecall).
- Off-chain or independently-sourced validation tools that verify transaction intent through a channel separate from the software being used to sign.

**How to check:**
- Identify what interface privileged signers use to review and approve transactions (e.g., a web-based multisig UI like Safe{Wallet}, a custom admin panel).
- Check whether the protocol or its signers use any independent transaction-verification method beyond trusting the display shown by a single web interface — for example, verifying transaction calldata directly against a hardware wallet's own screen (not just the connected software's display), or using a separate, independently-sourced verification tool to confirm what a transaction actually does before signing.
- Specifically check whether the review process distinguishes between a standard transfer/call and a delegatecall — the latter can transfer control of a wallet's underlying logic and is a documented, real-world attack vector (Bybit), but typically has no human-readable representation in a standard multisig interface, making it especially easy to disguise.
- Check whether any past security review or audit has specifically addressed this attack class (sometimes referred to as a "blind signing" risk) rather than only addressing key custody and threshold design.

**Match criteria:**
- EXACT MATCH: signers rely solely on a single web-based interface to review transactions with no independent verification step, regardless of how strong the underlying multisig threshold or key custody otherwise is.
- SIMILAR MATCH: some independent verification practice is mentioned or plausible (e.g., hardware wallets with their own transaction-detail screens) but it is not confirmed that signers actually use that independent display rather than trusting the connected software's summary.
- NOT PRESENT: documented practice of independently verifying transaction details through a channel separate from the primary signing interface (e.g., confirmed use of a hardware wallet's own screen to manually verify calldata, not just approve a summary shown by connected software), for every privileged signer.

**Important framing note:** a strong rating on Patterns 1 and 3 (verifier independence, key custody) should never be read as implying protection against this pattern — they are independent questions, and Radiant Capital's case is the clearest demonstration that a protocol can score well on those and still be defeated this way.

## What this file does NOT cover

- Smart contract code bugs in the bridge's own contract logic (e.g., the Wormhole 2022 signature verification flaw) — this is a code-logic issue, not a verifier/governance/custody pattern, and should be flagged as CANNOT DETERMINE / refer to professional audit unless a specific known code pattern is being checked.
- Replay attacks across message types sharing a nonce sequence — this is an emerging 2026 pattern with limited validated case history; flag as a SIMILAR MATCH / watch item only, not a scored EXACT MATCH, until a real incident validates it.
