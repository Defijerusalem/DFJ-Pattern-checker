# DFJ Pattern Checker

A library of DeFi exploit patterns validated against real, dated incidents — not theoretical risks. Built by [DeFiJerusalem](https://github.com/DeFiJerusalem) to be used as a [Claude Code](https://docs.claude.com) skill. It checks a protocol's contracts, documentation, or audit reports against failure modes that have already cost the industry real money — and says plainly when it can't tell.

**This is a pattern-matching tool, not a vulnerability-discovery tool.** It does not find new bugs. It checks whether known, named, dated categories of failure are present. If you're looking for an audit, this is not one — see [What this is not](#what-this-is-not) below.

---

## Why this exists

Most security tooling in DeFi either audits one contract deeply (expensive, slow, doesn't scale across thousands of protocols) or scores protocols from the outside without showing its reasoning. This project takes a third approach: build a small number of patterns, each one tied to a real incident with a name, a date, and a dollar figure — and only trust a pattern once it's been confirmed at more than one protocol, independently.

That second part matters. A pattern built from a single incident is a hypothesis. A pattern confirmed twice, at unrelated protocols, with the same root mechanism, is something closer to a law. Several patterns in this library exist *because* the first version, tested in good faith, turned out to be wrong or too narrow — those corrections are part of the public record here, not edited out.

## What it checks

Eight categories, each with its own file under `references/`:

| Category | What it watches for |
|---|---|
| Lending | Collateral concentration, cross-chain backing dependency, exotic token integration, curator/allocator risk |
| DEX/AMM | Spot-price manipulation, flash-loan pool-ratio distortion, downstream oracle-integration misreads |
| Bridge | Verifier/validator independence, failover behavior, key custody, signing-interface spoofing |
| Derivatives | Leverage/liquidity mismatch, oracle/mark-price latency, asymmetric settlement risk |
| Stablecoin | Mint authority control, collateral liquidity depth, off-chain operational dependency |
| Yield Aggregator | Deprecated strategy retirement, donation-manipulable vault accounting |
| RWA | Off-chain custody/key risk, oracle/proof-of-reserves integrity |
| Insurance | Capital pool adequacy, correlated claims-assessor conflict of interest, voter apathy |

Plus three checks that run regardless of category, defined in `SKILL.md`: whether a protocol still operates before any pattern is checked against it, whether risk is inherited from an underlying protocol it depends on, and whether a concentrated set of parties (a governance vote, an admin multisig, a validator set) could take unilateral action over user funds.

## What every pattern is actually built on

Every pattern here ties back to a real, named incident — not a hypothetical. A sample, not exhaustive:

- **Aave / KelpDAO, April 2026 ($292M)** — Aave's own contracts were never compromised. The loss came from accepting a liquid restaking token backed by a single-verifier cross-chain bridge as collateral. This is the case that the Lending and Bridge files were originally built around.
- **Radiant Capital (Oct 2024, $53M) and Bybit (Feb 2025, $1.4–1.5B)** — same attacker group, same compromised software, two unrelated organizations: a multisig's hardware-wallet signers approved a transaction that looked routine on screen but wasn't what they thought they were signing. Confirmed twice before being trusted.
- **Centrifuge's private credit pools** — a single price-admin key submits off-chain NAV with no independent on-chain check. Real, dated defaults (Harbor Trade Credit, ConsolFreight) show this isn't theoretical.
- **Nexus Mutual vs. KelpDAO** — the largest DeFi insurer's entire seven-year claims history is smaller than one mid-size hack. Not a claim of bad faith — a finding about capital scale.
- **Euler Finance ($197M)** — included as a *negative* result. Six professional audits missed it. This pattern library would not have caught it either, and says so. A library that claimed to catch everything would be less trustworthy than one that's honest about its edges.

## What this is not

- **Not an audit.** It does not read every line of a contract looking for novel bugs. It checks for patterns that have already happened elsewhere.
- **Not a security score.** DeFiJerusalem's full methodology is a separate, more comprehensive system. This pattern library is one input among several, not a replacement.
- **Not unbiased by documentation quality.** Protocols with thin or non-English documentation will return more "can't determine" results — not because they're riskier, but because there's less public material to check. This is stated explicitly in `SKILL.md` and should never be read as a finding of risk.
- **Not validated equally across every chain.** EVM chains (Ethereum, Base, BNB Chain, Arbitrum) have the deepest testing. EVM-compatible chains (Tron) and other ecosystems (Solana, Cosmos, Sui) have each been checked at least once and held up well, but with less repetition than EVM.

## How it's structured

```
SKILL.md              ← entry point: workflow, cross-cutting checks, known limitations
references/
  lending.md
  dex-amm.md
  bridge.md
  derivatives.md
  stablecoin.md
  yield-aggregator.md
  rwa.md
  insurance.md
```

Each reference file only loads when its category applies — checking a stablecoin doesn't pull in the bridge file unless that stablecoin actually depends on one.

## Using it

This is built as a [Claude Code](https://docs.claude.com) skill. There are three ways to set it up depending on how you work.

### Setup

**Option A — Work inside the repo (simplest)**

```bash
git clone https://github.com/DeFiJerusalem/DFJ-Pattern-checker
cd DFJ-Pattern-checker
claude  # opens Claude Code in this directory; the skill loads automatically
```

**Option B — Add to your own project**

Copy `SKILL.md` and the `references/` folder into your project's `.claude/` directory:

```
your-project/
  .claude/
    SKILL.md
    references/
      lending.md
      bridge.md
      ...
```

Claude Code will pick up the skill automatically when you open your project.

**Option C — Install globally**

Copy `SKILL.md` and `references/` into `~/.claude/` so the skill is available in every Claude Code session regardless of directory.

---

### Invoking the skill

Once set up, invoke it with the slash command:

```
/dfj-pattern-checker [protocol name or description]
```

Or just ask naturally — Claude Code will recognise when a request matches this skill:

> "Check Aave for known exploit patterns"
> "Is this protocol exposed to flash loan price manipulation?"
> "Run a DeFiJerusalem pattern scan on the contracts I'm about to integrate"

---

### What to provide

The skill works best when given real inputs. Provide whichever of these you have — you don't need all of them:

| Input | How to provide | What it unlocks |
|---|---|---|
| **Contract source code** | Paste inline, share a file, or give an Etherscan/Solscan/explorer link | Deterministic checks: TWAP vs. spot price, multisig threshold, mint cap presence |
| **Audit report** | Paste PDF text or a link | Scope confirmation, known-issue checks, oracle and key custody findings |
| **Protocol docs** | Link or paste | Oracle setup, collateral types, admin structure |
| **Just the protocol name** | Name alone | Web research is used; more findings will be CANNOT DETERMINE due to relying on public sources only |

If nothing is available, the skill will say so rather than guess. CANNOT DETERMINE is an honest output, not a negative finding.

---

### Pre-deployment / pre-integration checklist

Before deploying a new protocol or integrating an external one as collateral, an oracle source, or a yield strategy, run the following:

**1. Identify the category**
Is it a lending market, DEX/AMM, bridge, derivatives platform, stablecoin, yield aggregator, RWA protocol, or insurance fund? If it spans multiple categories, each gets its own check.

**2. Share the contract code or a verified on-chain address**
```
/dfj-pattern-checker
Here's the contract: [paste source or Etherscan link]
Category: Lending
```

**3. Share any available audit reports**
Audit reports often contain the oracle setup, admin key structure, and known-issue disclosures that are hardest to verify from contract code alone.

**4. For any protocol you're building on top of, check the underlying too**
A yield aggregator built on a lending market with a concentrated-collateral problem inherits that problem. The skill checks inherited risk automatically, but it needs to know what the underlying protocol is.

**5. Pay specific attention to these outputs before deploying:**
- Any **EXACT MATCH** — stop and investigate before proceeding
- **SIMILAR MATCH on Concentrated Control Risk** — means a small number of parties can take a severe action over the protocol; relevant for any integration where you're putting user funds into it
- **CANNOT DETERMINE on oracle setup** — means you haven't confirmed how pricing works; verify manually before using the protocol's price as an input to your own contracts
- **Per-chain consistency: CANNOT DETERMINE** — if you're deploying on a chain other than the protocol's primary chain, the security configuration may differ; verify the specific deployment

---

### What you get back

Every check ends with two outputs:

**Technical findings** — one entry per pattern, structured as:
> Pattern name → EXACT MATCH / SIMILAR MATCH / NOT PRESENT / CANNOT DETERMINE → specific evidence (the line, function, or document that triggered the finding) → confidence note

**Plain-language Breakdown** — same findings rewritten for someone with no DeFi or security background. One entry per pattern, each one explaining the underlying concept before stating what was found. Suitable for sharing with non-technical stakeholders.

Both outputs end with an explicit scope reminder: this is a pattern check, not an audit, and NOT PRESENT does not mean safe.

## Confidence levels, explained plainly

- **EXACT MATCH** — the specific failure mechanism is present. High confidence.
- **SIMILAR MATCH** — structurally close but not identical, or the evidence is incomplete. Needs a human to look closer.
- **NOT PRESENT** — checked, and this specific pattern wasn't found. This does not mean the protocol is safe. It means this one check came back clean.
- **CANNOT DETERMINE** — not enough public information exists to check this. Treated as a distinct, non-negative outcome — never implied to be a risk finding.

## Contributing / corrections

If you find a pattern here that's wrong, overclaimed, or missing a real counter-example — open an issue. Several patterns in this library exist in their current, narrower form *because* someone (in this case, ongoing internal testing) pushed back on an earlier, broader version. That process doesn't stop at publication.

## License

[Add license here before publishing.]
