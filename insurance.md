# Insurance Pattern Library

Validated against: sector-wide capital adequacy data (Nexus Mutual, the largest DeFi insurer, ~$81.56M total capital pool and ~$18M in cumulative claims paid since 2019, against the April 2026 KelpDAO exploit alone totaling $292M — 16x the insurer's entire seven-year claims history in a single incident). No incident exists of a major DeFi insurer failing to pay a legitimate claim due to bad-faith denial — this file deliberately does not include a "claims denial" pattern, because no validating case was found; Nexus Mutual's actual claims record (Yearn, FTX, Euler, Rari Capital, Arcadia Finance) shows consistent payouts. The validated risk in this category is capital scale, not claims-process integrity.

**Verified detail on the FTX case specifically (for accuracy in future outputs):** following FTX's November 2022 collapse, Nexus Mutual's claims assessors reviewed roughly 27 FTX Custody Cover claims; the large majority were approved and paid (paying out nearly $5 million total in February 2023), with a small number of denials (3 claims) for narrow procedural reasons — e.g., one claim was filed before the cover's required 90-day waiting period had elapsed. This was not a broad coverage-scope denial of FTX claims as a category. At the time, FTX-related liabilities represented approximately 4.33% of the capital pool, and the pool had sufficient capital to cover all eligible claims at that scale. This is useful evidence that Nexus Mutual's capital and claims process work as designed at the scale of events it has actually faced — it does not contradict Pattern 1's finding that the same capital base would be overwhelmed by a single event at KelpDAO's scale ($292M, vs. FTX's ~$8.79M in exposed cover). Do not describe the FTX outcome as a denial or scope-rejection in any output using this file — that would misstate the verified record.

## Why this category is distinct from every other file

Every other file in this library checks whether a protocol holding or moving user funds can fail. This file checks a different question: whether a protocol whose entire purpose is *absorbing other protocols' failure risk* actually has the capital and structure to do so. An insurance protocol's own contracts can be perfectly secure and it can still fail at its actual job if its capital pool is too small relative to the risks it underwrites.

## Global evidence-quality standard

A clean NOT PRESENT requires a specific, named, verifiable fact — actual disclosed capital pool size, total active cover outstanding, and a stated methodology for how claims assessment avoids conflicts of interest. Vendor language ("robust capital reserves," "trusted claims process," "comprehensive coverage") is never sufficient on its own.

## Pattern 1: Capital Pool Adequacy Relative to Underwritten Risk

**What to check:** the insurer's total capital pool size and total active cover outstanding, compared against the realistic scale of a single major exploit in the categories it insures.

**Why this matters — real, quantified case:**
- As of this library's research, Nexus Mutual — the largest and longest-running DeFi insurer — held a total capital pool of roughly $81.56 million, having paid approximately $18 million in claims across its entire operating history since 2019. The April 2026 KelpDAO bridge exploit alone totaled $292 million in losses — 16 times the insurer's entire historical claims experience, and more than three times its total capital pool. Less than 2% of DeFi's total value locked carries any insurance coverage at all, and total active cover across the entire insurance sector is estimated at a few hundred million dollars against hundreds of billions of dollars in TVL across the protocols that need protection.
- This is not a Nexus Mutual-specific problem — it is industry-wide. InsurAce's capital pool peaked at $150 million and has since collapsed to roughly $132,000, having completed only one major claim (the 2022 UST depeg) in its operating history. Sherlock's capital pool shrank from $60 million to roughly $505,000 within a single year. Unslashed Finance has several million dollars effectively stuck in unmaintained code, unchanged since late 2024. Two separate protocols (Cantina, launching a Native Protocol Cover product in March 2025) have publicly acknowledged the same structural conclusion this pattern describes: on-chain capital pools are not sized for on-chain correlated risk.
- The underlying actuarial problem, not just a funding gap: traditional insurance works because risks across policyholders are largely uncorrelated (one person's house fire doesn't cause another's). DeFi exploits do not have this property — a single bridge or oracle failure can simultaneously trigger claims across many protocols that share the same dependency (the same KelpDAO incident affected Aave, SparkLend, and Fluid simultaneously). A capital pool sized for uncorrelated risk is structurally undersized for correlated risk.

**How to check:**
- Find the insurer's current total capital pool size and total active cover outstanding (most DeFi insurers publish this on-chain or via a public dashboard).
- Compare this to the TVL of the largest single protocol or correlated-risk cluster the insurer covers — if a realistic worst-case single incident in that cluster would exceed a meaningful fraction of the total capital pool, this is a structural adequacy concern regardless of the insurer's track record.
- Check whether the insurer discloses any reinsurance, capital backstop, or claim-size capping mechanism for unusually large incidents.

**Match criteria:**
- EXACT MATCH: total capital pool is smaller than the TVL of a single major protocol or correlated cluster it actively covers, with no disclosed reinsurance or claim-capping mechanism.
- SIMILAR MATCH: capital pool size is disclosed but its adequacy relative to correlated-risk scenarios is not independently modeled or stress-tested in any available public information.
- NOT PRESENT: capital pool size, reinsurance/backstop arrangements, and correlated-risk stress-testing are disclosed and the insurer's exposure to any single covered protocol or cluster is capped well below total capital.

**Important framing note for any output using this pattern:** a SIMILAR or EXACT MATCH finding here is not a claim that the insurer is acting in bad faith or has ever failed to pay a legitimate claim — the validated cases (Nexus Mutual's actual payout history) show the opposite. This pattern measures whether the capital base could withstand a claim at the scale the broader DeFi ecosystem has already demonstrated is possible, separate from the insurer's willingness or historical track record to pay.

## Pattern 2: Correlated Claims-Assessor Conflict of Interest

**What to check:** who assesses and votes on whether a claim is paid, and whether those assessors have a direct financial stake in the outcome of their own vote.

**Why this matters — structural finding, not a specific incident:**
- In community-voting-based DeFi insurance models, the members who vote to approve or deny a claim are often the same pool of stakers whose locked capital would be reduced if the claim is paid — creating a direct, structural financial incentive to vote against paying. Traditional insurers separate underwriting, claims assessment, and capital provision into distinct roles specifically to avoid this conflict; some DeFi insurance models combine these functions by design.

**How to check:**
- Identify the claims assessment mechanism: is it community vote by capital-pool stakers, a separate third-party assessor, or a parametric (automatic, on-chain-condition-triggered) payout?
- For community-vote models, check whether voters have a disclosed, direct financial stake in the outcome of the specific claim they are voting on.
- Parametric models (automatic payout on a defined on-chain condition, e.g., a stablecoin trading below a peg threshold for a set duration) structurally avoid this conflict by removing discretionary human assessment — note this as a distinct, generally favorable design choice when found.

**Match criteria:**
- EXACT MATCH: claims are assessed and approved by the same pool of stakers whose capital is directly reduced by a successful claim, with no disclosed mitigation (e.g., no independent assessor option, no parametric trigger).
- SIMILAR MATCH: some mitigation exists (e.g., a third-party assessor option, partial parametric triggers) but the core conflict is not fully removed.
- NOT PRESENT: claims are assessed via a parametric mechanism with no discretionary human vote, or via assessors with no direct financial stake in the specific claim's outcome.

## Pattern 3 (low confidence — single case, not yet independently confirmed): Voter Apathy / Herding Incentive Risk

**What to check:** in claims-assessment models that separate voting power from financial exposure (i.e., the people voting on a claim are not the same people whose capital is reduced if it's approved — the opposite structure from Pattern 2), whether voters have any genuine incentive to assess a claim carefully, or whether they are rewarded simply for voting with the eventual majority outcome regardless of whether that outcome was correct.

**Why this is flagged at low confidence:** this pattern has only one validating case so far, and every other pattern in this library was added only after being independently confirmed at two separate protocols. Treat this pattern as a real, plausible structural concern worth checking for, not yet a confirmed, repeatable failure mode the way Pattern 1 and Pattern 2 are. Do not assign EXACT MATCH using this pattern until a second independent case is found; treat any finding here as SIMILAR MATCH at most.

**The single case so far:** Neptune Mutual (closed ~November 2024) architecturally separated the two roles Pattern 2 targets — NPM token holders voted on incidents (stake-weighted), while stablecoin liquidity providers bore the actual payout cost. NPM tokens were explicitly not used for claim payouts, so voters' own capital was not at risk either way they voted. This avoided Pattern 2's specific conflict-of-interest mechanism, but research into the protocol's incentive design suggested a different problem: voters earned rewards for voting with the majority outcome regardless of whether that outcome was correct, which incentivizes conformity to perceived consensus rather than independent, careful assessment — a meaningfully different failure mode (apathetic herding) than the one Pattern 2 describes (motivated denial).

**How to check:**
- Identify whether the claims-voting mechanism rewards voters based on the accuracy of their individual assessment, or based on whether they voted with the eventual majority.
- Check whether voters bear any financial consequence at all — gaining or losing — tied to the real-world outcome of the claim, separate from whether their vote matched the majority.
- If voters are rewarded purely for majority alignment with no stake in getting the substantive answer right, this is the structural condition the pattern describes.

**Match criteria:**
- SIMILAR MATCH (current ceiling for this pattern): voting power is separated from financial exposure (as in Pattern 2's NOT PRESENT case), AND voters are rewarded for majority alignment rather than for individually verifiable accuracy, with no disclosed mechanism encouraging independent assessment.
- NOT PRESENT: voting incentives are tied to individually verifiable accuracy (e.g., rewards or penalties based on whether a vote matched a later-confirmed correct outcome, not just the contemporaneous majority), or some other disclosed mechanism discourages pure herding behavior.

## What this file does NOT cover

- Whether a specific historical claim was correctly approved or denied on its individual merits — this file assesses structural capital and process risk, not the correctness of any single past claims decision.
- Premium pricing fairness or whether insurance is "worth it" economically for a given user (a separate, real concern raised by industry commentary — net yield after premiums can be negative for higher-risk protocols — but this is a cost/value question, not a security pattern).
