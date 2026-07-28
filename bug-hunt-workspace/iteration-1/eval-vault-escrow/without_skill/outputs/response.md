# Security Audit — TradeEscrow.sol

I read through the contract in detail, tracing every function's state transitions and every ETH transfer. Overall the design intent (buyer deposits → seller ships → buyer confirms, with a propose‑then‑confirm dispute path requiring both an arbiter *and* the admin multisig) is sound on paper, but the implementation has two critical bugs that break that model, plus several design gaps that weaken it further. I would **not** deploy this as-is. Details below, roughly in order of severity.

---

## Critical

### 1. `confirmResolution` deletes the pending resolution *before* reading it — payouts silently go to `address(0)` for `0` wei

```solidity
function confirmResolution(uint256 tradeId) external onlyRole(DEFAULT_ADMIN_ROLE) {
    PendingResolution storage pending = pendingResolutions[tradeId];
    if (!pending.exists) revert NotDisputed();
    Trade storage trade = trades[tradeId];

    trade.status = Status.Resolved;
    delete pendingResolutions[tradeId];                         // <-- zeroes the slot `pending` points at

    (bool ok, ) = pending.recipient.call{value: pending.amount}(""); // <-- reads the now-zeroed slot
    if (!ok) revert TransferFailed();

    emit ResolutionConfirmed(tradeId, pending.recipient, pending.amount); // <-- also reads zeroed slot
}
```

`pending` is a `storage` **reference**, not a copy. It's a pointer to the `pendingResolutions[tradeId]` slot. `delete pendingResolutions[tradeId]` zeroes that slot in place, and because `pending` aliases the same storage location, every subsequent access to `pending.recipient` / `pending.amount` reads the *zeroed* values, not the ones that were staged. Solidity storage pointers do not snapshot values at assignment time — each member access is a fresh `SLOAD` at the time it's evaluated.

Concretely: `pending.recipient` reads back as `address(0)` and `pending.amount` as `0`. The subsequent call becomes `address(0).call{value: 0}("")`. A zero‑value call to an address with no code trivially succeeds (`ok == true`), so:

- **No funds ever move.** The ETH that was supposed to go to the winning party stays locked in the contract.
- **No revert occurs**, so nothing looks wrong from a transaction‑success standpoint — you'd only catch this by asserting the recipient's balance actually changed.
- The trade is marked `Status.Resolved` anyway, so the trade can never be revisited — the funds are now **permanently stranded** with no code path to recover them (no sweep/rescue function exists either — see Medium #9 below).
- The emitted `ResolutionConfirmed` event reports `recipient = address(0), amount = 0`, which is misleading to any off-chain indexer/monitoring trying to reconcile what happened.

**This means every single dispute that goes through the intended "arbiter proposes, admin confirms" path — the mechanism the contract's own NatSpec describes as the safe, two-key way to move disputed funds — currently pays out nothing and permanently locks the money.** This is the single most severe bug in the contract; it makes the entire arbitration payout flow non-functional.

**Fix:** cache the values (or the whole struct) into memory before deleting, e.g.:
```solidity
address recipient = pending.recipient;
uint256 amount = pending.amount;
trade.status = Status.Resolved;
delete pendingResolutions[tradeId];
(bool ok, ) = recipient.call{value: amount}("");
if (!ok) revert TransferFailed();
emit ResolutionConfirmed(tradeId, recipient, amount);
```

---

### 2. `recuseAndRefund` has no role check at all, and `arbiter` is an arbitrary, buyer-chosen address — buyer can self-refund unilaterally

```solidity
function openTrade(address seller, address arbiter) external payable returns (uint256 tradeId) {
    ...
    trades[tradeId] = Trade({ buyer: msg.sender, seller: seller, arbiter: arbiter, ... });
}

function recuseAndRefund(uint256 tradeId) external {
    Trade storage trade = trades[tradeId];
    if (trade.buyer == address(0)) revert TradeNotFound();
    if (trade.status != Status.Disputed) revert NotDisputed();
    if (msg.sender != trade.arbiter) revert NotAuthorized();   // <-- only equality check, no onlyRole(ARBITER_ROLE)

    trade.status = Status.Resolved;
    uint256 amount = trade.amount;
    (bool ok, ) = trade.buyer.call{value: amount}("");
    if (!ok) revert TransferFailed();
}
```

Two facts compound into a critical access-control break:

1. `openTrade` accepts `arbiter` as a completely free-form `address` parameter — it is **never checked** against `ARBITER_ROLE` (or against anything) at trade-creation time. Any buyer can put any address here, including their own address or a second wallet they control.
2. `recuseAndRefund` — unlike `proposeResolution` — carries **no `onlyRole(ARBITER_ROLE)` modifier**. It only checks `msg.sender == trade.arbiter`.

Put together, a buyer can:
1. Call `openTrade(seller, myOwnAddress)` (naming themselves, or a sockpuppet, as the "arbiter").
2. Deposit the trade amount as normal.
3. At any point while `Open` (e.g., **after the seller has already shipped goods off-chain**), call `raiseDispute` (buyer is allowed to dispute their own trade).
4. Immediately call `recuseAndRefund` as `msg.sender == trade.arbiter` (themselves) — no role required — and receive a full refund of the escrowed amount.

This completely defeats the dispute-resolution trust model the contract's docstring describes ("a single arbiter signer can't unilaterally move funds without a second, independent confirmation from the admin multisig"). `recuseAndRefund` is a fully unilateral, single-transaction escape hatch that requires **zero privileged role** and **zero counter-signature**, and it's trivially reachable by the buyer themselves. In practice this means a buyer can always take their money back on demand, at any time before confirming delivery, regardless of whether the seller already performed — sellers have no real protection.

(Note this is *independent* of bug #1 — even if #1 is fixed, this hole remains and is arguably worse, since it doesn't even require a bug in the confirm path; it's a straightforward missing authorization check.)

**Fix, two changes needed together:**
- Add `onlyRole(ARBITER_ROLE)` to `recuseAndRefund` (matching `proposeResolution`).
- Validate in `openTrade` that `hasRole(ARBITER_ROLE, arbiter)` is true (or otherwise restrict who can be named as a trade's arbiter) — otherwise you can still end up with a "recognized" arbiter address that later loses the role, or a legitimate role-holder who was never meant to be tied to that specific trade.

---

## High

### 3. `openTrade` never validates that `arbiter` actually holds `ARBITER_ROLE` — can permanently lock disputed funds

Related to #2 but worth calling out as its own risk even after #2 is fixed: because `arbiter` is unchecked at trade-creation time, a trade can easily end up with an `arbiter` field pointing at an address that doesn't hold `ARBITER_ROLE`. Once such a trade is disputed:

- `proposeResolution` requires `onlyRole(ARBITER_ROLE)` — that specific named arbiter can never call it if they were never granted the role.
- The admin-fallback clause (`!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)`) only helps if the admin **also** happens to hold `ARBITER_ROLE` (the modifier is checked first, on top of the internal check) — nothing guarantees that.
- `recuseAndRefund` (once properly gated per fix #2) will also require the caller to hold `ARBITER_ROLE`.

If none of the above conditions are met, a disputed trade has **no path to resolution at all** — the funds are stuck in `Status.Disputed` forever, with no recovery mechanism. This should be prevented at the source: `openTrade` should require `hasRole(ARBITER_ROLE, arbiter)` before accepting the trade.

---

## Medium

### 4. Split resolutions are documented but not actually implementable — any attempted split permanently strands the remainder

The NatSpec for `proposeResolution` says the arbiter can decide "full refund to buyer, full release to seller, **or a split**." But `PendingResolution` only has a single `recipient` / `amount` pair, and `confirmResolution` only ever performs one transfer. There is no mechanism to pay two parties out of one resolution. If an arbiter ever proposes, say, `amount = trade.amount / 2` intending the other half to go to the other party, only the named `recipient` gets paid (modulo bug #1, in which nobody gets paid) — the remaining `trade.amount - pending.amount` is never sent anywhere, the trade is marked `Resolved`, and that remainder is permanently orphaned in the contract with no code path to ever claim it. The docstring's promised "split" functionality is simply not supported by the data model.

### 5. Admin fallback in `proposeResolution` isn't gated on arbiter unresponsiveness — the two-key guarantee can quietly collapse to one key

```solidity
if (trade.arbiter != msg.sender && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAuthorized();
```

The docstring frames the admin fallback as being "if the assigned arbiter goes dark," but the code enforces no such precondition — any address that holds both `ARBITER_ROLE` and `DEFAULT_ADMIN_ROLE` can propose a resolution for *any* disputed trade at any time, overriding a perfectly responsive, correctly-assigned arbiter. Since `DEFAULT_ADMIN_ROLE` is, by default in OpenZeppelin's `AccessControl`, the role-admin for `ARBITER_ROLE`, nothing stops the admin from simply granting itself `ARBITER_ROLE` and then single-handedly calling both `proposeResolution` and `confirmResolution` — i.e., moving disputed funds with **one key**, exactly the scenario the contract's own comments say is impossible by design ("so a single arbiter signer can't unilaterally move funds ... without a second, independent confirmation"). If the intent is genuine dual-control, the contract should enforce that the admin and the arbiter cannot be the same `msg.sender` for a given resolution (e.g., require `proposedBy != confirmer`), and/or should not let admin substitute for the arbiter unconditionally.

### 6. `proposeResolution` never validates that `recipient` is the trade's buyer or seller

```solidity
function proposeResolution(uint256 tradeId, address recipient, uint256 amount) external onlyRole(ARBITER_ROLE) {
    ...
    if (amount > trade.amount) revert ZeroAmount();
    pendingResolutions[tradeId] = PendingResolution({ recipient: recipient, ... });
}
```

`recipient` is fully arbitrary — there's no check that it equals `trade.buyer` or `trade.seller`. A compromised arbiter key (or an arbiter colluding with, or being, the confirming admin per #5) could redirect disputed funds to any third-party address, and `confirmResolution` performs no independent sanity check either. Given resolution requires only one admin confirmation with no re-validation of the proposal's substance, I'd add a require that `recipient == trade.buyer || recipient == trade.seller` as cheap defense-in-depth.

---

## Low / Informational

- **Misleading error selection:** `proposeResolution` reverts with `ZeroAmount()` when `amount > trade.amount` — that's not a "zero amount" condition at all. Doesn't affect security, but will confuse anyone debugging a revert (consider a dedicated `AmountExceedsTrade` error).
- **No timeout / auto-release:** If the buyer never calls `confirmDelivery` and neither party disputes, funds sit in `Open` indefinitely. The seller does have `raiseDispute` as recourse, but that recourse is only as good as the dispute-resolution path being functional (see Critical #1 and #3) — worth adding a time-based escape hatch (e.g., auto-release to seller after N days of buyer inaction, or vice versa) as defense-in-depth.
- **No sweep/rescue function:** Given bugs #1, #3, and #4 all create realistic scenarios where ETH gets permanently stranded in the contract, there is no admin recovery mechanism at all. Even with those bugs fixed, it's good practice to have a guarded rescue path for genuinely stuck funds (e.g., ETH sent outside the normal flow).
- **No zero-address / self-trade checks in `openTrade`:** `seller` and `arbiter` aren't checked against `address(0)` or against `msg.sender` (buyer). A buyer could accidentally (or intentionally, per Critical #2) set `seller == address(0)` or `arbiter == buyer`. Cheap to guard against at the input-validation layer.
- **No zero-address check on `admin` in the constructor:** if `admin` is ever passed as `address(0)`, `DEFAULT_ADMIN_ROLE` is granted to the zero address and the contract has no admin at all — nobody could ever grant `ARBITER_ROLE` or call `confirmResolution`. Worth an explicit `require(admin != address(0))`.
- **Push-payment pattern with no reentrancy guard:** To the contract's credit, checks-effects-interactions is followed correctly in all three payout functions (status is updated / pending resolution deleted *before* the external `.call`), so direct same-trade reentrancy is blocked and a failed transfer correctly reverts the whole transaction (undoing the status change too). Still, given how much of this contract's remaining safety rests on getting the ordering exactly right, I'd add OpenZeppelin's `ReentrancyGuard` as belt-and-suspenders, and consider a pull-payment model (credit balances, let recipients withdraw) to avoid forcing external call semantics into the settlement functions altogether — that also sidesteps griefing where a seller/recipient contract with a reverting `receive()` can block `confirmDelivery`/`confirmResolution` for that specific trade.

---

## Summary

The two critical issues are not edge cases — they are the default, everyday behavior of the contract's core dispute-resolution flow:

1. **`confirmResolution` reads a storage struct's fields *after* deleting it**, so every admin-confirmed resolution pays out `0` wei to `address(0)`, silently, with no revert — the escrowed funds are simply stuck forever, while the trade is marked `Resolved` and can never be retried.
2. **`recuseAndRefund` has no `ARBITER_ROLE` check, and the `arbiter` address is chosen unchecked by the buyer at trade creation** — meaning a buyer can name themselves as their own trade's "arbiter" and unilaterally refund themselves at any time, with no counter-signature, completely bypassing the propose/confirm safeguard the contract's docs describe.

Together, these two bugs mean the arbitration system currently can never actually pay a seller through the intended dispute path, while a buyer can always get their money back on demand. I'd fix both before doing anything else, then address the High/Medium items (arbiter-role validation at trade creation, real split-resolution support or removing that claim from the docs, and tightening the admin/arbiter trust boundary) before considering this ready for funds at risk on mainnet. I'd also strongly recommend a fresh test suite that asserts actual ETH balance changes after `confirmResolution` (not just transaction success) — that's exactly the kind of check that would have caught bug #1 immediately.
