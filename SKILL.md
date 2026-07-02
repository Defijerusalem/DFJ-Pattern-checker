---
name: dfj-pattern-checker
description: Checks a DeFi protocol's smart contract code, documentation, or audit reports against a library of validated, real-world exploit patterns (collateral concentration, bridge verifier weaknesses, privileged mint authority, AMM price manipulation, leverage/liquidity mismatches, deprecated code, donation-manipulable vault math). Use this skill whenever the user wants to check a protocol for known risk patterns, wants a DeFiJerusalem-style security/risk assessment, mentions auditing or screening a contract for "known exploit types," or asks "is this protocol exposed to X" where X resembles a pattern in the library. This is a PATTERN-MATCHING tool, not a vulnerability-discovery tool — it does not find novel bugs, and must never be described as doing so.
---

# DFJ Pattern Checker

## What this skill does, and does not do

This skill checks protocol code/docs/audits against a fixed library of patterns, each validated against at least one real, dated exploit. It is an aggregator-style check, not an audit.

**It does:** flag exact or close matches to patterns that have already caused real losses elsewhere in DeFi.

**It does NOT:** find new, never-seen vulnerability classes. Six professional audit firms missed the Euler Finance donateToReserves flaw before it was exploited for $197M — this skill would not have caught that either, because it had no prior pattern to match against. Never claim or imply this skill replaces professional audits or can find arbitrary novel bugs.

**Always state this distinction to the user** when presenting results — every output should make clear whether a finding is an EXACT MATCH (high confidence, maps directly to a validated pattern) or a SIMILAR/PARTIAL MATCH (lower confidence, structurally resembles a pattern but isn't identical — needs human review, do not auto-score with the same confidence).

## Workflow

0. **Determine whether this is a pre-deployment design check or a post-deployment protocol check.**

   This skill can operate at two points in a protocol's lifecycle:

   **Pre-deployment (design review):** The user submits a completed `PRE_DEPLOYMENT_TEMPLATE.md` or equivalent design spec document describing a protocol that has not yet been deployed. No live contracts exist to check. The input is the design decisions themselves — oracle choice, mint authority structure, bridge verifier configuration, admin key setup — described in plain language or a structured document.

   **Post-deployment (live protocol):** The user names a live protocol and provides or requests contract code, audit reports, and documentation. This is the standard workflow described in steps 1–12 below.

   **How to tell which mode you are in:**
   - If the user submits a completed `PRE_DEPLOYMENT_TEMPLATE.md` or equivalent filled document — run the pre-deployment check directly against it (workflow below).
   - If the user describes a protocol they are building in plain language without a filled template — enter **conversational intake mode** (see below).
   - If the user names an existing protocol or provides a contract address — this is a post-deployment check, proceed to Step 1.
   - If unclear, ask: "Is this protocol already deployed, or are you checking a design before building?"

   ---

   **Conversational Intake Mode**

   When a user says they are building a protocol but has not filled in the template, do not ask them to fill it in manually. Instead, conduct a structured interview and generate the spec from their answers.

   **How it works:**

   a. **Open with one question:** "What are you building?" — get the protocol type and a brief description. Do not ask multiple questions at once.

   b. **Identify the category from their answer.** Load the relevant reference file(s) silently. Then ask only the questions that map to patterns in those files — do not ask questions about categories that do not apply.

   c. **Ask one question at a time.** Move through the relevant sections of the template in order. Do not front-load all questions. Wait for each answer before asking the next one.

   d. **Accept plain language answers.** The user does not need to know DeFi security terminology. If they say "a backend service holds the key that mints tokens," that is enough to check against Stablecoin Pattern 1. Translate their language into pattern criteria internally — do not make them do it.

   e. **Flag undecided answers immediately.** If the user says "we haven't decided that yet" or "I'm not sure," flag it immediately as a CANNOT DETERMINE finding and note it must be resolved before deployment. Do not wait until the end to surface it.

   f. **When enough information has been gathered** — either all relevant pattern questions have been answered, or the user indicates the design is complete — generate the spec automatically:
      - Write out the filled `PRE_DEPLOYMENT_TEMPLATE.md` from the conversation
      - Save it as a file the user can keep
      - Immediately run the pre-deployment check against it without asking the user to do anything else

   g. **Output the findings** following the pre-deployment workflow below. The user never sees the template as a form to fill in — they just have a conversation and get findings.

   ---

   **Example intake conversation:**

   User: "I'm building a stablecoin backed by ETH and US Treasuries."
   Checker: "Who or what authorises new tokens to be minted — is it an on-chain smart contract with enforced rules, a multisig, or a single key?"
   User: "A backend service. The key is stored in AWS."
   Checker: [internally: Stablecoin Pattern 1 — EXACT MATCH candidate]
   Checker: "Is there an on-chain cap on how much can be minted per transaction or per day?"
   User: "Not yet."
   Checker: [flags: CANNOT DETERMINE — no on-chain cap defined]
   Checker: "Who manages the US Treasury exposure off-chain, and how is the backing verified on-chain?"
   ...and so on until findings are complete.

   ---

   **Pre-deployment check workflow:**

   a. **Confirm operating status is N/A.** The protocol does not exist yet — skip Step 1's operating status check entirely.

   b. **Identify the category from the template's Section 1.** Proceed to load the relevant reference file(s) exactly as in Step 3 below.

   c. **Check each pattern against the design decisions, not live contract data.** The underlying question for every pattern is the same — only the evidence source changes. Instead of reading a contract's multisig threshold on-chain, you read the threshold stated in the design document. Instead of checking a live oracle configuration, you check the oracle design described in the spec.

   d. **Treat blank or unanswered fields as CANNOT DETERMINE, not as NOT PRESENT.** A blank answer means the design decision has not been made yet — this is the most important finding a pre-deployment check can surface. Flag every blank field in a relevant section explicitly: "This decision has not been documented. It must be made and reviewed before deployment."

   e. **Output pre-deployment findings, not a score.** The output is a list of design decisions that match known failure patterns, decisions that are undocumented (CANNOT DETERMINE), and decisions that are clean (NOT PRESENT). Do not produce a numeric score — the protocol is not live and the full methodology cannot be applied. State clearly: "These are pre-deployment findings against known structural failure patterns. They reflect design decisions, not deployed code. A clean result here does not mean the implementation will be safe."

   f. **Close with a prioritised fix list.** For every EXACT MATCH or CANNOT DETERMINE finding, state: what the finding is, what the known failure looks like (cite the real incident from the reference file), and what a clean design decision looks like instead. Order findings by severity — EXACT MATCH first, then CANNOT DETERMINE, then SIMILAR MATCH.

1. **Check whether the protocol is still operating before running a full pattern scan.** A meaningful share of protocols that would otherwise be flagged by this library turn out to be shut down, in formal wind-down, operating at a small fraction of historical scale, or actively frozen/in incident response by the time they're checked — this has happened often enough in testing that it must be checked first, not discovered partway through. State whichever of these applies plainly as the first thing in the output, before any pattern findings:
   - **Shut down:** e.g., "This protocol shut down in [month/year]."
   - **Formal wind-down:** e.g., "This protocol is in formal wind-down, with current TVL of $X compared to a peak of $Y."
   - **Actively frozen / mid-incident-response:** a distinct status from the two above — the protocol has not shut down or wound down, but funds or contracts are currently paused or frozen following a recent incident, often before a post-mortem has been published. State this plainly too, e.g., "This protocol's vaults/contracts are currently frozen following a [date] incident; a full post-mortem had not been published as of this check." Treat the specific technical root cause as CANNOT DETERMINE if no post-mortem exists yet, even if the general failure category (e.g., access control, oracle manipulation) is reported in early coverage — early reporting on an unresolved incident is a lower-confidence source than a completed post-mortem.
   - **Operating normally:** no special framing needed; proceed to the full pattern scan as usual.

   Pattern findings for a non-normally-operating protocol should still be reported (they remain genuinely instructive — a protocol's history of failures is real evidence), but they should be clearly framed relative to its actual current status, not presented as if reporting on a fully normal, currently active protocol. Do not let a detailed technical write-up about a dead, winding-down, or frozen protocol read the same way as one about a live, fully operating protocol — the practical relevance to a reader is completely different in each case.

2. **Identify the protocol's primary category.** Lending, DEX/AMM, Bridge, Derivatives/Perpetuals, Stablecoin/CDP, Yield Aggregator, RWA (Real-World Asset), or Insurance. If the protocol spans multiple categories (e.g., a lending protocol with an integrated DEX), check it against all applicable category reference files, scored separately per product if the products are materially distinct in TVL or function — do not blend them into one score.

3. **Load only the relevant reference file(s)** from `references/` based on category. Each reference file contains that category's validated patterns, the real case(s) that validated them, and concrete things to look for in code/docs/audits.

4. **Check for inherited risk before checking the named protocol's own patterns.** Many protocols wrap or build on top of another protocol — a yield aggregator depositing into a lending market, a stablecoin using a DEX pool's price as a reference, a vault providing liquidity that itself depends on a bridge. Identify any underlying protocol(s) the one being checked materially depends on, and check those underlying protocols against their own relevant reference file. Any unresolved EXACT MATCH or SIMILAR MATCH finding on an underlying protocol should be disclosed as inherited risk on the protocol being checked, even if that protocol's own contract logic passes cleanly. A clean wrapper around a risky underlying protocol is not a clean result.

5. **Check for Concentrated Control Risk, regardless of category.** This is a cross-cutting check, not specific to any one reference file — apply it alongside whichever category-specific pattern(s) are in use. The underlying question is always the same: how many genuinely independent parties have to collude to take a severe, unilateral action over user funds or the system itself? This question has shown up validated at multiple different layers: a lending protocol's governance vote (Solend's SLND1 proposal to seize a whale's account, passed with 97.5% approval even though one wallet cast 88% of the votes, before being reversed the next day after backlash), a bridge or stablecoin's admin multisig (Frax's 3-of-5 core team multisig controlling the Comptroller and Timelock, which pushed an undisclosed contract patch in December 2025), and a base-layer validator/consensus set (a custom L1 where core contributors hold a large, concentrated share of the staked token that determines block production and consensus weight). These are the same risk at different layers — governance, admin role, and consensus — not three separate patterns.

   **How to check:** identify any mechanism (a governance vote, an admin multisig, a validator/staking weight system) that could let a concentrated set of parties take a severe, unilateral action — seizing funds, pushing an unreviewed upgrade, or controlling consensus outcomes. Check how concentrated the actual power behind that mechanism is (disclosed voting/stake/key distribution, or its absence), and whether any friction exists (cooldown, supermajority requirement, independent veto) that would slow down or block a concentrated actor from acting unilaterally.

   **Match criteria:**
   - EXACT MATCH: a mechanism for severe unilateral action exists, the power behind it is demonstrably or verifiably concentrated in a small number of parties, and no meaningful friction exists.
   - SIMILAR MATCH: the mechanism exists but concentration data is undisclosed or unverified, or friction exists but is untested under a real concentrated-actor scenario.
   - NOT PRESENT: no mechanism for unilateral severe action exists, or power is verifiably distributed with no small group able to act alone.

   Present this check as its own labeled finding distinct from whatever category-specific patterns were also checked, since it cuts across categories rather than belonging to one.

6. **Check per-chain deployment consistency for any protocol live on more than one blockchain.** This is a separate cross-cutting check from Concentrated Control Risk above. Many protocols (Frax, Pendle, Stargate, and most major lending/stablecoin/bridge protocols) deploy the same product across multiple chains — but security configuration is not guaranteed to be identical across those deployments. A bridge verifier set, an admin multisig's signer composition, or an oracle setup can differ chain by chain, even under one brand name. Do not treat a finding verified on one chain (e.g., "Frax's DVN setup") as automatically true for every chain the protocol is deployed on.

   **How to check:** identify every chain the protocol is materially deployed on (not just its primary/origin chain). For the patterns being checked (especially Bridge and Concentrated Control Risk patterns, which are the most likely to vary by deployment), check whether the configuration is confirmed to be the same across chains, confirmed to differ, or simply unverified per-chain. If a protocol's general marketing or documentation describes a security property "at a glance" without specifying which deployment it applies to, treat that as unverified for any specific chain rather than assuming it holds everywhere.

   **Match criteria, applied per relevant pattern:**
   - If configuration is confirmed identical and strong across all material deployments: the underlying pattern's NOT PRESENT/EXACT MATCH finding can be stated to apply protocol-wide.
   - If configuration varies by chain, or has only been verified for one deployment: state findings per-chain rather than protocol-wide, and explicitly flag that other deployments are unverified — do not let a strong finding on the origin chain imply the same strength everywhere.
   - If no information exists on whether configuration is consistent across deployments at all: state this as CANNOT DETERMINE for the multi-chain consistency question specifically, separate from whatever was found on any single chain.

7. **Gather inputs.** Ask the user for, or look for, whichever of these are available — do not require all of them:
   - Contract/program source code (e.g., Etherscan/BscScan for EVM chains; Solscan or a Solana program explorer for Solana; Mintscan for Cosmos-based chains; the relevant explorer for Move-based chains like Aptos or Sui — use whichever explorer matches the protocol's actual chain, not Etherscan by default)
   - Audit reports (PDF or linked reports)
   - Protocol documentation describing collateral types, oracle setup, governance/admin structure
   If none are available, say so plainly rather than guessing — do not score a protocol from name recognition alone.

8. **Check each pattern in the relevant reference file(s) against the inputs.** For each pattern, output one of:
   - **EXACT MATCH** — the specific mechanism described in the pattern is present (e.g., a single-signer/1-of-1 verifier, a privileged mint function with no on-chain cap)
   - **SIMILAR MATCH** — structurally resembles the pattern but differs in a material way (e.g., a 2-of-3 multisig where all three signers are the same team with no time-lock) — flag for human review explicitly, do not assign the same confidence as an EXACT MATCH
   - **NOT PRESENT** — checked, pattern not found. State plainly that this means "not flagged by this specific check," not "safe" — absence of a known pattern is not the same as absence of risk.
   - **CANNOT DETERMINE** — insufficient information was provided to check this pattern. Say so rather than guessing.

9. **Distinguish what's mechanically checkable from what needs judgment.** Some checks are deterministic (does the contract have a TWAP function call, what's the numeric multisig threshold in the contract) — if the user has code available and asks for it, suggest these could be scripted checks rather than relying on LLM reading for things a parser could verify exactly. Reserve LLM judgment for the harder calls: reading audit report prose to determine if a function was actually in scope, judging whether a partial match is close enough to flag.

10. **Present results category by category**, using the structure: pattern name → match status → evidence found (quote/cite the specific line, function, or audit statement that supports the determination) → confidence level. Never present a finding without pointing to what specifically triggered it.

11. **End with an explicit reminder** that this check covers known patterns only, is not a substitute for a professional audit, and that "NOT PRESENT" results across all patterns do not mean the protocol is safe — only that it wasn't flagged by this specific, limited check.

12. **Always close with a "Breakdown," separate from the detailed findings — written for someone with no DeFi or security background, not just a shorter version of the analyst output.** This is not a summary that compresses jargon; it's a teaching explanation that assumes the reader doesn't know what a multisig, an oracle, or a bridge verifier is, but is curious about something they're actually using or considering using. Structure this as a breakdown — one entry per finding, not a single flowing narrative — so each result is still individually identifiable, the same way the technical findings are, just written in plain language. Rules for the Breakdown:

   - **No color signal, score, or numeric rating**, for the same reason as before — this is a pattern check, not the full DeFiJerusalem methodology score, and a number or color risks being mistaken for one.
   - **Open with one sentence stating what kind of result this is** (substantive findings vs. mostly unverifiable) in plain language, before listing anything.
   - **Then give one entry per category/pattern actually checked**, each with a short plain-language label (not the pattern's technical name) followed by: the underlying concept explained in one or two plain sentences, then the real technical term in parentheses right after the explanation (so the reader has something to recognize and search later, e.g., "...think of them like witnesses signing off on a delivery (this role is technically called a *verifier* or *DVN*)."), then what was found, then — if knowable — what it means for the reader concretely. Example structure for one entry:
     - **Moving money between blockchains:** When this protocol moves your assets between two different blockchains, it relies on outside parties to confirm the transfer really happened — think of them like witnesses signing off on a delivery (this role is technically called a *verifier*, and the network of them a *DVN*). We couldn't confirm how many independent verifiers are required, or whether they're actually separate companies rather than the same team wearing different hats. This matters most if you're moving a large amount through this pathway.
   - **Introduce one or two technical terms per entry at most, only the ones most worth knowing** — not every possible term. The goal is to give the reader a foothold to search further if curious, not to turn the Breakdown into a glossary. Bold or italicize the term so it visually stands out from the surrounding plain language.
   - **Use a real, simple analogy or a known comparable event where it genuinely helps, but don't force one for every entry.** A reference to "the kind of setup that let an attacker drain $292 million from a different bridge in 2026" is useful context, not fear-mongering, when accurate and relevant — skip it if forced or if the finding has no clean parallel.
   - **Keep each entry short — a few sentences, not a paragraph.** The Breakdown should be scannable: a reader should be able to skim labels and stop on the one they care about, the same way they could skim the technical findings table.
   - **Always end with one plain sentence making the scope limit clear in non-technical language** — e.g., "This only checks for a specific list of problems that have caused real losses before. It can't catch a brand-new kind of problem nobody has seen yet, and it doesn't mean the protocol is safe just because nothing showed up here."

## Known limitations — read before presenting any result as final

**This pattern library was built and validated almost entirely against EVM (Ethereum Virtual Machine) chains — Ethereum, Base, BNB Chain, Arbitrum, and similar.** The underlying risk *concepts* in every pattern are chain-agnostic (a single point of trust in cross-chain verification, a privileged mint key with no caps, thin liquidity under leverage — none of these care what virtual machine or programming language a protocol runs on). However, several reference files use EVM-specific terminology in their verification instructions — terms like "EOA" (externally-owned account, an Ethereum account-model concept), `balanceOf()`, `getConfig()`/`setConfig()`, or "ERC-20"/"ERC-777" as if they were universal standards. They are not. When checking a protocol on a non-EVM chain (Solana, Cosmos-based chains, Move-based chains like Aptos or Sui, Bitcoin-adjacent chains, etc.), translate the underlying question to that chain's actual account and token model rather than searching for the literal EVM term — e.g., on Solana, the equivalent question to "is this an EOA or a smart contract wallet" is "is this a standard keypair-controlled wallet or a Squads multisig/program-controlled account," and the equivalent of an ERC-20 standard-conformance check is whatever that chain's own token program or standard actually specifies. This library has not been independently stress-tested against a non-EVM protocol — treat any output for a non-EVM chain as a reasonable-effort translation of the underlying concept, not a fully validated check the way EVM-chain results are.

**This skill's coverage is biased toward well-documented protocols, and that bias is structural, not incidental.** Every pattern in this library was validated against incidents that received real press/research coverage (CoinDesk, The Defiant, Rekt News, primary protocol docs). That means:

- Protocols with polished documentation, active GitHub repos, and third-party explainers will produce more EXACT MATCH / NOT PRESENT determinations — more *information*, in either direction.
- Protocols with thin, non-English, or Discord/Telegram-only documentation will produce more CANNOT DETERMINE results — not because they're necessarily riskier, but because there's less public material to check against.
- **CANNOT DETERMINE must never be allowed to visually or numerically resemble a negative finding.** A protocol returning five CANNOT DETERMINE results is not the same as a protocol returning five SIMILAR MATCH or EXACT MATCH results, even though both "look incomplete." Always state explicitly: "insufficient public information was available to assess these patterns" as a distinct category from "these patterns were checked and risk was found."
- Do not infer or imply that thin documentation itself is evidence of risk within this skill's pattern-matching output. Documentation quality may be a legitimate separate signal elsewhere in a fuller methodology (e.g., a dedicated Documentation score component), but conflating "we couldn't check" with "we checked and it's risky" inside this skill's output would misrepresent what was actually done.
- When a protocol returns mostly CANNOT DETERMINE, say so as the headline finding, not a footnote — e.g., lead with "Limited public documentation was available for this protocol; most patterns could not be independently verified" before listing individual pattern results.
- This skill's pattern library itself was built from a small number of high-profile incidents per category (1-3 each). It has not been validated against the long tail of smaller, less-covered protocol failures, which may fail in ways not yet captured by any pattern here. Treat the pattern library as a check against known, named failure modes — not a comprehensive risk assessment.

## Reference files

- `PRE_DEPLOYMENT_TEMPLATE.md` — structured design review template for protocols not yet deployed. Submit this filled-in document to trigger a pre-deployment check (Step 0 above) instead of a live protocol check.
- `references/lending.md` — collateral concentration, cross-chain backing dependency, exotic token integration risk, curator/allocator risk
- `references/dex-amm.md` — spot-price manipulation, flash loan pool-ratio distortion, downstream oracle-integration misreads
- `references/bridge.md` — verifier/validator independence, failover behavior, key custody architecture, signing-interface spoofing
- `references/derivatives.md` — leverage/liquidity mismatch on thin order books, oracle/mark price latency, asymmetric settlement risk
- `references/stablecoin.md` — privileged mint authority risk, collateral liquidity depth risk, off-chain operational/counterparty dependency risk
- `references/yield-aggregator.md` — deprecated/legacy strategy retirement risk, donation-manipulable vault math
- `references/rwa.md` — off-chain custody/operational key risk, oracle/proof-of-reserves integrity risk
- `references/insurance.md` — capital pool adequacy relative to underwritten risk, correlated claims-assessor conflict of interest, voter apathy/herding incentive risk

Load only the file(s) matching the protocol's category. Do not load all eight for every check.

## Explicitly out of scope for this skill

- Novel code-logic bugs with no prior real-world pattern (Euler, GMX V1 reentrancy) — these require professional audit-grade review, not pattern matching
- Liquid Staking/Restaking as a standalone category — no validated standalone incident exists; instead check LST/LRT-using protocols against `bridge.md` (if cross-chain dependent) and `lending.md` (if used as collateral elsewhere)
- Legal, regulatory, or business-model risk assessment
- **Business viability / economic sustainability risk (e.g., GameFi tokenomics collapse, NFT marketplace shutdowns due to low volume, protocol attrition from unsustainable yield models).** A protocol winding down because its business model failed economically is a fundamentally different question from a protocol being exploited — this skill checks for known exploit and security-failure patterns only. Do not apply this skill's patterns to assess whether a protocol's economics, token incentive design, or market viability will hold up over time; that is a separate analytical question outside this skill's scope, and conflating the two would misrepresent what a "no findings" result actually means.
