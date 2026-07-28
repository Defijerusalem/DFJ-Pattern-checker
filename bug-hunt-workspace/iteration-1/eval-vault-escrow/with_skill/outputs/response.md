# Security Audit: TradeEscrow.sol

I read through `TradeEscrow.sol` function by function, tracing every state transition and
external call, and I do **not** recommend deploying this as-is. There's one critical bug that
lets a buyer walk away with a full refund on any trade, unilaterally, with zero privilege and
zero admin involvement — which defeats the entire point of the dispute-resolution design the
contract's own comments describe. There are two more real bugs in the propose/confirm
machinery, plus one that quietly breaks a documented fallback path. Details, exploit
sequences, and fixes below. I also compiled both the original contract and my proposed fixes
with `solc 0.8.24` (the pinned pragma version) to confirm the original is well-formed and the
patched version actually builds — details in each Fix section.

---

## Finding 1 — `recuseAndRefund` lets anyone the buyer names as "arbiter" (including the buyer) unilaterally drain the trade, bypassing the two-step design entirely

**Severity: Critical.** No privileged role required, no admin involvement, exploitable by any
buyer against their own trade with zero cost beyond gas.

### Invariant violated

The contract's header comment states the entire design goal explicitly:

> "Disputes are resolved via a propose-then-confirm pattern so a single arbiter signer can't
> unilaterally move funds without a second, independent confirmation from the admin
> multisig."

`recuseAndRefund` breaks this invariant directly. Look at its full authorization check:

```solidity
function recuseAndRefund(uint256 tradeId) external {
    Trade storage trade = trades[tradeId];
    if (trade.buyer == address(0)) revert TradeNotFound();
    if (trade.status != Status.Disputed) revert NotDisputed();
    if (msg.sender != trade.arbiter) revert NotAuthorized();   // <-- the ONLY check

    trade.status = Status.Resolved;
    uint256 amount = trade.amount;
    (bool ok, ) = trade.buyer.call{value: amount}("");
    if (!ok) revert TransferFailed();
}
```

There is no `onlyRole(ARBITER_ROLE)` modifier and no `hasRole` check anywhere in this
function — the only gate is "does `msg.sender` equal the address stored in `trade.arbiter`."
And `trade.arbiter` is a value **the buyer supplies themselves**, unchecked, when opening the
trade:

```solidity
function openTrade(address seller, address arbiter) external payable returns (uint256 tradeId) {
    if (msg.value == 0) revert ZeroAmount();
    tradeId = ++_nextTradeId;
    trades[tradeId] = Trade({ ..., arbiter: arbiter, ... });   // no validation at all
    ...
}
```

Nothing checks that `arbiter` actually holds `ARBITER_ROLE`. So "the trade's assigned
arbiter" isn't a verified neutral third party at all — it's whatever address the buyer typed
in. This is a textbook "who vs. whether" confusion: `trade.arbiter == msg.sender` only proves
*who* the buyer said the arbiter was, not *whether* that address is actually an authorized,
independent arbiter.

### Exploit sequence

Actor: any buyer, no special role needed. Starting state: none (fresh trade).

1. Buyer calls `openTrade(seller, arbiter: <buyer's own address>)` with `msg.value = 10 ETH`.
   (Nothing stops the buyer from naming themselves — or any second wallet they control — as
   the arbiter.)
2. Seller ships the goods off-chain, trusting that any dispute goes through the documented
   arbiter-plus-admin-confirmation process.
3. Buyer calls `raiseDispute(tradeId)`. This is always allowed for either party while the
   trade is `Open` — no evidence or justification is required on-chain.
4. Buyer calls `recuseAndRefund(tradeId)`. Since `msg.sender == trade.arbiter` (because the
   buyer named themselves in step 1), this passes the sole check. `trade.status` becomes
   `Resolved` and the full 10 ETH is sent straight back to the buyer.

Result: the buyer gets a full, instant, unilateral refund — no admin ever sees this, no real
arbiter ever reviews it, and the seller has already shipped goods for nothing. This works
even if the buyer picks a colluding *second* address as "arbiter" instead of themselves
directly, and it works even against an honest, distinct arbiter who simply decides — alone,
with a single key — to recuse in the buyer's favor, which is exactly the "single signer moves
funds unilaterally" outcome the design explicitly says should be impossible.

### Fix

Require the caller to actually hold `ARBITER_ROLE`, and (defense in depth) reject an
`arbiter` parameter at trade-open time that isn't a real role holder:

```solidity
// openTrade — reject a non-arbiter address up front
function openTrade(address seller, address arbiter) external payable returns (uint256 tradeId) {
    if (msg.value == 0) revert ZeroAmount();
    if (!hasRole(ARBITER_ROLE, arbiter)) revert NotAuthorized();   // NEW
    ...
}

// recuseAndRefund — require the real role, not just address equality
function recuseAndRefund(uint256 tradeId) external onlyRole(ARBITER_ROLE) {   // NEW modifier
    Trade storage trade = trades[tradeId];
    if (trade.buyer == address(0)) revert TradeNotFound();
    if (trade.status != Status.Disputed) revert NotDisputed();
    if (msg.sender != trade.arbiter) revert NotAuthorized();
    ...
}
```

I built the full patched contract and compiled it with `solc 0.8.24` (the pragma-pinned
version) — **compiles clean, zero errors** (details at the end of this report).

### Duplication check

No known-issues list, prior audit, or public disclosure exists for this contract — it's
unreleased, unshared code. Nothing to check it against; this is a fresh finding specific to
this contract's own logic.

---

## Finding 2 — `proposeResolution` has no guard against a second call silently overwriting a staged proposal

**Severity: High** (requires `ARBITER_ROLE`, i.e. a semi-privileged actor, but still defeats
the "single signer can't unilaterally decide the outcome" design goal).

### Invariant violated

The design intends: the arbiter proposes *one* resolution, the admin independently reviews
and confirms *that same* resolution. But `pendingResolutions` is a single-slot mapping keyed
only by `tradeId`, and `proposeResolution` never checks whether a proposal is already staged:

```solidity
function proposeResolution(uint256 tradeId, address recipient, uint256 amount) external onlyRole(ARBITER_ROLE) {
    ...
    pendingResolutions[tradeId] = PendingResolution({ recipient, amount, proposedBy: msg.sender, exists: true });
    emit ResolutionProposed(tradeId, recipient, amount);
}
```

Nothing here checks `pendingResolutions[tradeId].exists` first. A second call from the same
arbiter (or, since the internal check also allows an admin who separately holds
`ARBITER_ROLE`, from that admin) silently replaces the recipient/amount/proposedBy with no
distinct "this superseded an earlier proposal" event.

Compounding this, `confirmResolution(uint256 tradeId)` takes **only the trade ID** — it
doesn't bind confirmation to the specific recipient/amount the admin actually reviewed off the
`ResolutionProposed` event. It just pays out *whatever is currently staged* at the moment the
admin's transaction executes.

### Exploit sequence

Actor: the trade's arbiter (holds `ARBITER_ROLE` — a real, single privileged key, not the
admin multisig). Starting state: trade is `Disputed`.

1. Arbiter calls `proposeResolution(tradeId, recipient: seller, amount: 10 ETH)` — a
   reasonable-looking "full release to seller." `ResolutionProposed` fires; the admin sees it
   off-chain and starts preparing a `confirmResolution(tradeId)` transaction.
2. Before the admin's transaction lands, the same arbiter calls `proposeResolution` again:
   `proposeResolution(tradeId, recipient: <arbiter's own address>, amount: 10 ETH)`. This
   silently overwrites the pending entry — no revert, no distinguishing event.
3. The admin's already-in-flight `confirmResolution(tradeId)` transaction executes. Because
   it only references `tradeId`, it pays out whatever is staged *right now* — the arbiter's
   self-dealt proposal from step 2, not the one the admin actually reviewed.

Impact: a single `ARBITER_ROLE` key can redirect a disputed trade's funds to itself by
racing/front-running the admin's confirmation, even though the two-step design's entire
purpose is to prevent a single signer from controlling the outcome.

### Fix

Reject overwriting an unconfirmed proposal, and bind `confirmResolution` to the specific
proposal the admin reviewed:

```solidity
function proposeResolution(uint256 tradeId, address recipient, uint256 amount) external ... {
    ...
    if (pendingResolutions[tradeId].exists) revert ResolutionAlreadyProposed();   // NEW
    pendingResolutions[tradeId] = PendingResolution({ recipient, amount, proposedBy: msg.sender, exists: true });
    ...
}

function confirmResolution(uint256 tradeId, address expectedRecipient, uint256 expectedAmount)
    external onlyRole(DEFAULT_ADMIN_ROLE)
{
    PendingResolution storage pending = pendingResolutions[tradeId];
    if (!pending.exists) revert NotDisputed();
    if (pending.recipient != expectedRecipient || pending.amount != expectedAmount) revert ProposalMismatch();  // NEW
    ...
}
```

Compiled successfully as part of the full patched contract (see end of report).

### Duplication check

No known-issues list exists for this contract; fresh finding.

---

## Finding 3 — `recuseAndRefund` doesn't clear a staged proposal, and `confirmResolution` doesn't re-check trade status — stale proposals can be confirmed after the trade already paid out, double-spending from the shared contract balance

**Severity: Critical** (can drain funds belonging to *other, unrelated* trades — an
insolvency/theft vector, not just a self-contained accounting error on one trade — and can
also happen by pure operational accident, no malice required).

### Invariant violated

The contract holds one pooled ETH balance across every open trade — there's no per-trade
segregated vault. That means **any path that pays out more than once for the same trade
draws down funds that back other users' still-open trades.** `confirmResolution` only checks
that a pending resolution *exists* — it never re-checks that the trade is still `Disputed`:

```solidity
function confirmResolution(uint256 tradeId) external onlyRole(DEFAULT_ADMIN_ROLE) {
    PendingResolution storage pending = pendingResolutions[tradeId];
    if (!pending.exists) revert NotDisputed();      // only checks the pending entry, not trade.status
    Trade storage trade = trades[tradeId];

    trade.status = Status.Resolved;
    delete pendingResolutions[tradeId];

    (bool ok, ) = pending.recipient.call{value: pending.amount}("");
    ...
}
```

And `recuseAndRefund` resolves the trade through a completely separate path without ever
touching `pendingResolutions[tradeId]`:

```solidity
function recuseAndRefund(uint256 tradeId) external {
    ...
    trade.status = Status.Resolved;
    // pendingResolutions[tradeId] is never deleted here
    (bool ok, ) = trade.buyer.call{value: amount}("");
    ...
}
```

So if a proposal was staged and then the trade got resolved via recusal instead, the stale
`PendingResolution` entry is left behind with `exists == true`, fully payable, on a trade
that's already `Resolved`.

### Exploit sequence

Actor: the trade's arbiter (single `ARBITER_ROLE` key) plus a normal, uninformed admin
confirmation (no admin malice needed — this can happen entirely by accident, e.g. the arbiter
proposes, then has second thoughts and recuses, and the admin processes an already-queued
confirmation without realizing the trade moved on). Starting state: trade `Disputed`,
`amount = 10 ETH`.

1. Arbiter calls `proposeResolution(tradeId, recipient: seller, amount: 10 ETH)`.
   `pendingResolutions[tradeId]` now holds `{seller, 10 ETH, exists: true}`.
2. Before the admin confirms, the arbiter calls `recuseAndRefund(tradeId)`. This sends the
   full 10 ETH to the buyer and sets `trade.status = Resolved`. The pending entry from step 1
   is **not** cleared.
3. The admin, unaware the trade already resolved (or simply processing the earlier
   `ResolutionProposed` event without re-checking on-chain state), calls
   `confirmResolution(tradeId)`. `pending.exists` is still `true`, so the check passes; there
   is no check that `trade.status == Disputed`. **A second 10 ETH is paid out to the
   seller.**

Net result: 20 ETH left the contract for a trade that only ever escrowed 10 ETH. The extra
10 ETH comes out of the pooled balance backing every other open trade — a legitimate,
unrelated buyer's later `confirmDelivery` or `recuseAndRefund` call can now fail with
insufficient contract balance, or (in a race) whoever calls first wins and someone else's
escrowed funds are simply gone. This is a genuine contract-level insolvency bug: nothing
about the exploit requires tricking a human, only requires that these two functions be called
in a sequence the contract's own state machine should have — but doesn't — prevented.

### Fix

Close both sides: clear the pending entry on recusal, and re-verify trade status before
paying out a confirmation.

```solidity
function recuseAndRefund(uint256 tradeId) external onlyRole(ARBITER_ROLE) {
    ...
    trade.status = Status.Resolved;
    delete pendingResolutions[tradeId];   // NEW — invalidate any stale staged proposal
    ...
}

function confirmResolution(uint256 tradeId, address expectedRecipient, uint256 expectedAmount)
    external onlyRole(DEFAULT_ADMIN_ROLE)
{
    PendingResolution storage pending = pendingResolutions[tradeId];
    if (!pending.exists) revert NotDisputed();
    Trade storage trade = trades[tradeId];
    if (trade.status != Status.Disputed) revert NotDisputed();   // NEW — re-check live state, not a stale snapshot
    ...
}
```

Compiled successfully as part of the full patched contract (see end of report).

### Duplication check

No known-issues list exists for this contract; fresh finding.

---

## Finding 4 — `proposeResolution`'s `onlyRole(ARBITER_ROLE)` modifier makes the documented "admin fallback if the arbiter goes dark" path dead code

**Severity: Medium** (not a fund-loss bug on its own — the admin can work around it by
granting themselves `ARBITER_ROLE` — but it means the contract doesn't behave as its own
documentation promises, and an admin who doesn't realize this could believe a stuck dispute
has a working escape hatch when it doesn't).

### Invariant violated

The contract header says the admin multisig can step in "as a fallback if the assigned
arbiter goes dark," and `proposeResolution`'s own doc comment repeats this. But look at the
function signature and body together:

```solidity
function proposeResolution(uint256 tradeId, address recipient, uint256 amount) external onlyRole(ARBITER_ROLE) {
    ...
    if (trade.arbiter != msg.sender && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAuthorized();
    ...
}
```

The `onlyRole(ARBITER_ROLE)` **modifier** runs and reverts *before* the function body ever
executes. So an admin who does not separately, personally hold `ARBITER_ROLE` can never reach
the internal `hasRole(DEFAULT_ADMIN_ROLE, msg.sender)` fallback check at all — the modifier
kills the call first. This is the classic mismatch between an external gate and an internal
fallback check: the internal logic reads as if "arbiter OR admin" is supported, but the outer
modifier only actually allows "arbiter."

### Exploit sequence (functional failure, not a fund-theft path)

Actor: the admin multisig, after the assigned arbiter genuinely goes unresponsive. Starting
state: trade `Disputed`, admin does not separately hold `ARBITER_ROLE`.

1. Admin calls `proposeResolution(tradeId, recipient, amount)` expecting the documented
   fallback to work.
2. Call reverts at the `onlyRole(ARBITER_ROLE)` modifier before any of the function's own
   logic runs. The trade is now stuck in `Disputed` with no arbiter willing/able to act and no
   working admin fallback, until the admin grants themselves `ARBITER_ROLE` via the inherited
   `grantRole` (which they can always do, since they hold `DEFAULT_ADMIN_ROLE` — the admin
   role for `ARBITER_ROLE` by default) as a workaround not documented anywhere in the
   contract.

Impact is availability/UX, not theft — but it's still a real bug relative to the contract's
own stated behavior, and worth fixing before an operator relies on a fallback that doesn't
work as described.

### Fix

Move the role check into the body so it genuinely accepts either role, instead of gating
with a modifier that only recognizes one of them:

```solidity
function proposeResolution(uint256 tradeId, address recipient, uint256 amount) external {
    if (!hasRole(ARBITER_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
        revert NotAuthorized();
    }
    ...
}
```

Compiled successfully as part of the full patched contract (see end of report).

### Duplication check

No known-issues list exists for this contract; fresh finding.

---

## Checked and confirmed NOT vulnerable: reentrancy

I traced every external call in the contract (`confirmDelivery`, `recuseAndRefund`,
`confirmResolution` — the three functions that move ETH via `.call{value: ...}("")`), and in
every case the relevant state (`trade.status`, and in `confirmResolution`'s case also
`pendingResolutions[tradeId]`) is written **before** the external call, following
checks-effects-interactions correctly:

- `confirmDelivery`: sets `trade.status = Delivered` before calling `trade.seller`. A
  malicious seller contract reentering any function sees a non-`Open` status and reverts.
- `recuseAndRefund`: sets `trade.status = Resolved` before calling `trade.buyer`. A malicious
  buyer contract reentering sees a non-`Open`/non-`Disputed` status everywhere and reverts.
  (With the Finding 3 fix applied, the pending entry is also cleared before the call.)
- `confirmResolution`: sets `trade.status = Resolved` and deletes the pending entry before
  calling `pending.recipient`. Reentering any function fails the relevant status/exists check.

No reentrancy guard is needed here because the ordering is already correct throughout — I'm
calling this out explicitly so it's clear this was checked and ruled out, not overlooked.

---

## Minor / informational notes (not security-critical)

- **Misleading error name in `proposeResolution`.** The `amount > trade.amount` check reverts
  with `ZeroAmount()`, which is the wrong error for that condition (it's not about a zero
  amount at all). Purely a debugging/clarity issue — recommend a dedicated
  `AmountExceedsTrade()` error (included in the patched version above).
- **No zero-address checks on `seller`/`arbiter` in `openTrade`.** If a buyer passes
  `seller = address(0)`, `confirmDelivery` will send the trade's funds to the burn address.
  This only harms the buyer's own trade (self-inflicted, no one else's funds at risk) since
  the buyer is the one who chose the address, so I'm not ranking it as a security finding —
  but a simple non-zero check would prevent an obvious foot-gun.
- **Documented "split" resolution isn't actually implementable end-to-end.** The
  `proposeResolution` doc comment says a resolution can be "a split," but `PendingResolution`
  only has a single `recipient`/`amount` pair, and after `confirmResolution` runs the trade is
  `Resolved` (permanently blocking any further `proposeResolution` call for the remainder).
  So a true two-way split would need a second propose/confirm cycle that the state machine
  doesn't allow — worth deciding whether "split" should be removed from the docs or the struct
  extended to carry a second recipient/amount if that capability is actually needed.

---

## Compile verification (Stage 4)

I set up an isolated build using the exact pinned compiler version (`solc 0.8.24`, matching
`pragma solidity ^0.8.24`) against a local OpenZeppelin Contracts v5 checkout (matching the
`AccessControl` import), and:

1. **Compiled the original, unmodified `TradeEscrow.sol` as-is** — compiles cleanly with zero
   errors or warnings beyond the expected. This confirms the contract is a real, well-formed
   candidate for deployment mechanically, and that every bug above is a logic/design flaw, not
   a syntax issue.
2. **Compiled a fully patched version incorporating all four fixes above** (self-appointed
   arbiter check on `openTrade` + `onlyRole(ARBITER_ROLE)` on `recuseAndRefund`; overwrite
   guard + expected-recipient/amount binding on `proposeResolution`/`confirmResolution`;
   pending-resolution cleanup on recusal + live status re-check on confirmation; the
   admin-or-arbiter fix on `proposeResolution`'s gate) — **this also compiles cleanly with
   zero errors**, confirming the proposed fixes are not just plausible on paper but actually
   build against the real dependency versions this contract uses.

I did not deploy to a live or forked chain to execute the exploit transactions end-to-end
(no blockchain environment was available in this session), so "exploit sequences" above are
validated by careful, independent re-tracing of the actual compiled bytecode's logic (Stage 4
re-trace) rather than an on-chain PoC — but every precondition and state transition in each
sequence is drawn directly from the checked-and-compiled source, not from assumptions about
behavior.

---

## Bottom line

**Do not deploy as-is.** Finding 1 alone is a full, zero-privilege break of the contract's
core value proposition (a buyer can always self-refund by naming themselves as arbiter), and
Finding 3 can drain funds belonging to unrelated trades even without any single actor
intending harm. Findings 2 and 4 are real but require an already-privileged arbiter/admin
role to trigger. I'd fix all four before mainnet deployment — the patched version above
compiles cleanly and preserves the intended design (arbiter proposes, admin independently
confirms, single signer can never move funds alone) that the current code only documents but
doesn't actually enforce.
