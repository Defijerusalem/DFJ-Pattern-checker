# DFJ Pattern Check — Metric (Oracle-Anchored DEX)

**Input available:** Sherlock contest brief only — the sponsor's own answers to the
standard audit intake questionnaire, plus the in-scope file/nSLOC list for
`Metric-OMM/metric-core`, `Metric-OMM/metric-periphery`, and
`Oracle-Based-Pool/smart-contracts-poc`. **No Solidity source was available in this
session** (this session's GitHub access is scoped to `defijerusalem/dfj-pattern-checker`
only), so this check is closer to the "audit report / docs" tier than the "contract
source" tier described in this library's README — expect more CANNOT DETERMINE results
than a check with source access would produce.

**Operating status:** Not shut down, wound down, or frozen. Contracts have reportedly
already been through at least one prior audit round (a Zellic report and a separate
"Collaborative Audit Report" dated 2026-07-06) and are now under an active Sherlock
contest, with a router deployment the sponsor describes as already live via CREATE3 on
Ethereum + Base. Treat as an operating/pre-general-availability protocol under active
security review, not a mature protocol with track record.

**A note on category fit, upfront:** this library's `dex-amm.md` file was validated
against classic constant-product/concentrated-liquidity AMMs (Cetus, KiloEx,
PancakeSwap) whose core risk is a manipulable on-chain reserve ratio. Metric is a
structurally different design — it has **no internal price discovery at all**; pool
liquidity is repriced entirely off an external oracle/price-provider. That means
Pattern 1 and Pattern 2 below don't map 1:1 onto Metric's architecture — they're
applied by translating the underlying question ("can price be pushed away from fair
value, and does anything downstream trust that pushed price?") rather than by literally
searching for a spot-price/reserve-ratio read. Flagged explicitly per pattern below.

---

## Category-specific findings (`dex-amm.md`)

### Pattern 1 — Spot-Price-Only Pricing (No TWAP) → **SIMILAR MATCH** (architecture-shifted)

Metric doesn't have this pattern in its literal form (there's no reserve ratio to read
because there's no internal price discovery — the sponsor states this directly:
"Pure oracle-anchored pricing — no internal price discovery... there's no DEX
cross-check, the only sanity guard is the Chainlink deviation check"). But the
*underlying risk this pattern exists to catch* — a manipulable price feeding
downstream settlement — has been moved wholesale onto the oracle/price-provider layer
instead of removed. The sponsor says as much: "manipulation risk shifts entirely to
the oracle/price-provider layer... If those guards are mis-tuned, bad-price execution
is possible."

Whether those guards are in fact well-tuned is a source-level question this brief
can't answer:
- The staleness/deviation/sequencer-down checks (`maxTimeDelta`/`maxRefStaleness`,
  Chainlink deviation, L2 sequencer-uptime via `ProtectedProviderL2`) are described,
  but their actual thresholds and whether every code path enforces them are
  **CANNOT DETERMINE** without source.
- The "downstream-integrator-misread" sub-check (does every consumer read the
  *clipped/anchored* price, never a raw provider value?) is exactly the shape of the
  Harvest/Curve distinction this file calls out. The brief states the anchored band is
  a hard invariant "including source mode," which is the right design intent, but
  whether the extensions (`OracleValueStopLossExtension`, `PriceVelocityGuardExtension`)
  and the router all consume the clipped getter rather than a raw one is
  **CANNOT DETERMINE** without source.
- Asset-specific oracle gap: pool creation is permissionless for any ERC-20
  token0<token1 pair, with no token-level allowlist (curation happens at the pool
  level via classification tiers/optional allowlist extensions, not the token level).
  That means a pool could be created for a yield-bearing or rebasing wrapped token
  where the anchored price-provider only tracks the underlying's price, not the
  wrapper's accruing exchange rate. Not confirmed either way — **SIMILAR MATCH**,
  unverified assumption, worth checking explicitly since USDC/USDT are the only named
  in-scope tokens and nothing rules out wrapped/yield tokens being paired.

### Pattern 2 — Pool Ratio Distortion via Auxiliary Mechanism → **SIMILAR MATCH** (architecture-shifted)

No classical burn/fee/donation mechanism is described. The closest structural analog
is the **AnchoredPriceProvider band-clipping mechanism** itself: a curator supplies an
arbitrary bid/ask, and the contract is supposed to clip it into `mid ± (u + floor)`
before it can affect a quote. The sponsor identifies this directly as the single point
of failure: "the band math (floor/uMax, ceil rounding) is the entire safety
boundary — an error there is the high-impact case." That is structurally the same
question Pattern 2 asks (can an externally-suppliable input distort the effective
price, and is it properly bounded?) — just applied to an oracle input rather than a
pool-balance mutation. Whether the clipping math is correct is a source-level
question — **CANNOT DETERMINE**.

A second, smaller analog: the sponsor's disclosed "rounding always favors the pool"
design (fees/baseFee/band edges use ceil, share math rounds against the user) is
explicitly flagged by the sponsor as something that "creates intentional rounding
asymmetry — worth checking it can't be amplified" — i.e., whether repeated small
trades can compound a rounding-favorable-to-pool edge into a larger, LP-favorable (or
attacker-favorable, if it can be flipped) distortion over many transactions. This is
the same "can a small per-trigger effect be replayed to a large cumulative effect"
question this pattern category cares about. **CANNOT DETERMINE** without source —
flagged as a specific, sponsor-acknowledged area worth checking for accumulation.

---

## Cross-cutting checks (apply regardless of category)

### Concentrated Control Risk → **SIMILAR MATCH**

Multiple roles can take unilaterally severe action over user funds:
- **Factory Owner** ("trusted"): sets protocol fee caps, sets `poolDeployer` (once),
  can pause the protocol, and can sweep treasury funds.
- **Oracle `ADMIN_ROLE`**: can blacklist, manage integrators/approved factories, and
  **`withdrawEth`**.
- **PriceProvider/AnchoredProvider factory admin** (AccessControl): "trusted," bounded
  parameters only.

Pool Admin is explicitly bounded (capped fees, timelock-gated parameter changes,
pause limited to its own pool) — that's the better-designed role here. But the brief
gives no information on **who or what actually holds** the Factory Owner role, the
Oracle `ADMIN_ROLE`, or the PriceProvider factory admin role: single EOA vs. multisig,
signer count/threshold, or whether any timelock applies to *these* roles' actions
(only Pool Admin's PP-change proposals are stated to be timelock-gated). A mechanism
for severe unilateral action exists (treasury sweep, `withdrawEth`); the concentration
of who controls it is undisclosed in this brief — **SIMILAR MATCH**, needs the actual
key-custody setup verified (ideally a Safe with a real signer threshold and a
timelock) before treating these roles as low-risk for integrators or LPs.

### Inherited risk (oracle/off-chain dependency)

Metric's own solvency, swap-conservation, and quote-sanity invariants are all
conditioned on upstream price sources — Chainlink, Pyth, a "Lazer" consumer, and
off-chain "compressed oracle" relayers — being correct and non-stale. The sponsor
states plainly that price updates, "especially for compressed oracles," are assumed
"always correct, and not stale," and explicitly puts this out of scope for the
contest. That's a reasonable scoping decision for the contest itself, but it means
Metric's actual security is inherited, not self-contained: anyone integrating a
Metric pool's price as an input elsewhere is really trusting the underlying oracle
network's correctness and liveness, one layer removed. Not a finding against Metric's
own code, but worth stating explicitly as inherited dependency, consistent with this
library's inherited-risk check.

### Per-chain deployment consistency → **CANNOT DETERMINE (partial)**

Ethereum and Base are confirmed by the sponsor to share identical CREATE3-deployed
router addresses — treat that pairing as consistent. **HyperEVM is a third target
chain named in the brief but not covered by that CREATE3 confirmation, and its
sequencer/execution model differs materially from an OP-stack/Arbitrum-style L2**,
which is what `ProtectedProviderL2`'s sequencer-uptime guard is presumably built
against. Whether HyperEVM has an equivalent sequencer-liveness signal at all, and
whether the same guard logic is even meaningful there, is not addressed in the brief.
**Flag explicitly: do not assume the Base-oriented L2 guards carry over to HyperEVM
without separate verification.**

---

## Explicit scope reminder

This is a **pattern check against a documentation brief, not an audit** — no Solidity
was read in this session. Every CANNOT DETERMINE above is a named, source-level
question (band-clipping math, rounding-accumulation, actual multisig/timelock
composition of the trusted roles, HyperEVM guard equivalence) that a reviewer with
source access should verify directly; it is not evidence of a problem. Every
NOT PRESENT/SIMILAR MATCH above reflects only what this specific, limited pattern
library checks for — it does not mean the protocol is safe, and it does not
substitute for the professional audits already under way.

---

## Breakdown (plain language)

This check is based on a written project description, not the actual code, so most
answers here are "we can't tell from what we have" rather than "we checked and it's
fine or risky" — keep that distinction in mind reading the rest.

- **How trades get priced:** Most decentralized exchanges figure out an asset's price
  from how much of it is sitting in their own liquidity pool at that moment (this is
  called the *reserve ratio* or *spot price*), which is a known target for attackers
  using large flash loans to briefly distort that ratio. Metric does something
  different on purpose: it doesn't use its own pool balances to set price at all — it
  just copies a price coming from an outside source (an *oracle*), like a Chainlink
  feed or an off-chain price service. That removes the classic flash-loan attack on
  the pool itself, but it means the entire question of "can the price be wrong or
  manipulated" moves onto that outside oracle instead of disappearing. The project's
  own team says this openly. We can't verify from this brief alone whether the
  guardrails around that oracle price (checks for staleness, checks for a suspicious
  jump) are strict enough — that needs the actual code.

- **The "safety band" around the price:** Metric lets a specially-approved party
  submit a price, but the contract is supposed to clamp that submitted price into a
  narrow allowed range around a reference midpoint before it can affect anyone's
  trade — think of it like a supervisor checking a cashier's till count is close
  enough to what the register says it should be, and correcting it if it's too far
  off. The project's own team calls the math behind this clamp "the entire safety
  boundary" — if there's a bug in exactly this spot, it's their own stated worst case.
  We don't have the code to check the math itself, so this is an open question, not a
  finding either way.

- **Who can just take money out or pause things:** A few roles in this system —
  the entity that owns the whole factory, and the admin of the price-oracle system —
  can do serious, one-shot things like pause the protocol, sweep treasury funds, or
  pull ETH out of the oracle contract (this kind of privileged account is often called
  an *admin role* or a *multisig*, depending on how many people have to agree before
  it acts). We don't know from this brief whether those roles are controlled by a
  single wallet or a multi-person multisig, or whether there's any waiting period
  before those actions take effect. That matters a lot if you're planning to deposit
  liquidity or build on top of this — it's worth asking directly before doing either.

- **Depending on the same three chains, in different ways:** Metric is meant to run
  on Ethereum, Base, and HyperEVM with the same contract addresses. Two of those
  three (Ethereum and Base) are confirmed to share the same addresses; HyperEVM isn't
  mentioned in that confirmation, and it's also a different kind of chain than
  Ethereum or Base in ways that could matter for a safety check built specifically
  around Base/Ethereum-style infrastructure. Not a red flag on its own — just an open
  question that anyone using the HyperEVM deployment specifically should chase down.

This is a check against a fixed list of failure patterns seen before elsewhere in
DeFi, based only on a written project description — it can't catch a brand-new kind
of bug nobody has seen yet, and a lack of red flags here does not mean the protocol
is safe to use or integrate with as-is.
