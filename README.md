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

This is built as a [Claude Code](https://docs.claude.com) skill. Clone the repo, point Claude Code at the folder, and ask it to check a protocol. It will tell you what it found, how confident it is, and what it couldn't verify — followed by a plain-language breakdown for anyone without a security background.

## Confidence levels, explained plainly

- **EXACT MATCH** — the specific failure mechanism is present. High confidence.
- **SIMILAR MATCH** — structurally close but not identical, or the evidence is incomplete. Needs a human to look closer.
- **NOT PRESENT** — checked, and this specific pattern wasn't found. This does not mean the protocol is safe. It means this one check came back clean.
- **CANNOT DETERMINE** — not enough public information exists to check this. Treated as a distinct, non-negative outcome — never implied to be a risk finding.

## Contributing / corrections

If you find a pattern here that's wrong, overclaimed, or missing a real counter-example — open an issue. Several patterns in this library exist in their current, narrower form *because* someone (in this case, ongoing internal testing) pushed back on an earlier, broader version. That process doesn't stop at publication.

## License

[Add license here before publishing.]
