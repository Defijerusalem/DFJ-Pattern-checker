# Y3 PoC — YearnRoleManager deploys unconfigurable DebtAllocators

Reproduces: `YearnRoleManager._deployAllocator()` (called from `newVault()`,
`addNewVault()`, and `updateDebtAllocator()`) initializes new per-vault
`DebtAllocator` clones with the **vault's own address** as governance, instead of
**Brain** — despite the function's own comment stating *"Deploy a new debt allocator
for the vault with Brain as the gov."* Since the vault contract has no function that
lets it act as `msg.sender` calling back into the allocator, every
`onlyGovernance`/`onlyManagers` function on that allocator becomes permanently
uncallable from the moment it's deployed.

Confirmed via a real, executed test calling the actual `newVault()` entry point
against the real, unmodified `YearnRoleManager.sol`, `DebtAllocatorFactory.sol`,
`DebtAllocator.sol`, and a real Vyper-compiled `VaultV3`/`VaultFactory` (only the
underlying asset is a mock).

## Setup

```
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts@v4.9.5 --no-commit
pip install vyper==0.3.10   # must be on PATH as `vyper`
```

(Ships with `lib/openzeppelin-contracts` and `lib/forge-std` as symlinks into another
checkout from my review environment — the `forge install` commands above replace
those with real checkouts.)

## Run

```
forge test --match-contract Y3_BrickedDebtAllocator -vvvv
```

Expected: `[PASS] test_newVaultGetsUnconfigurableDebtAllocator()`. The `-vvvv` trace
shows the full call: `newVault()` → deploys a real vault → `DebtAllocatorFactory.
newDebtAllocator(<vault address>)` → the resulting allocator's `governance()` equals
the vault address, and Brain/daddy both get rejected trying to configure it
afterward.

## Note on reachability

This bug only fires when the `ALLOCATOR_FACTORY` position on a `YearnRoleManager` has
been set to a live `DebtAllocatorFactory` (via `setPositionHolder`). If that position
is still `address(0)` on the deployed mainnet instance, `_deployAllocator` falls back
to a single shared allocator instead, and this specific path hasn't fired yet in
production. I couldn't confirm current mainnet state without RPC access — worth
checking `YearnRoleManager(<address>).getAllocatorFactory()` before treating this as
an active incident rather than a live landmine.
