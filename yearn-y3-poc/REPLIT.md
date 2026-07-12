# Running the Y3 mainnet-fork check on Replit

If this is a new Repl (not the one from the Y2 PoC), follow all steps. If it's the
same Repl as before, Foundry/Vyper are already installed — skip to step 3.

## 1. Install Foundry (skip if already done)
```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
```

## 2. Install Vyper (skip if already done)
```bash
pip install vyper==0.3.10
```

## 3. Upload and extract this project
Drag `y3-poc.tar.gz` into the Repl file pane, then in the Shell:
```bash
tar xzf y3-poc.tar.gz --strip-components=1
```
(If you still have the Y2 project in this Repl, put Y3 in its own folder/Repl to
avoid the two `foundry.toml`/`lib` setups colliding.)

## 4. Install dependencies
```bash
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts@v4.9.5 --no-commit
```

## 5. Confirm your ALCHEMY_MAINNET_URL Secret is set
Same Secret as before (Tools → Secrets). If this is a fresh Repl, add it again:
- Key: `ALCHEMY_MAINNET_URL`
- Value: your Alchemy mainnet HTTPS URL

## 6. Run the local PoC first (sanity check, no Alchemy key needed)
```bash
forge test --match-contract Y3_BrickedDebtAllocator -vvvv
```
Should show `[PASS]`.

## 7. Before running the fork test — verify the address is actually YearnRoleManager
The mainnet address I found (`0xb3bd6B2E61753C311EFbCF0111f75D29706D9a41`) comes from
Yearn's own deploy script, but there are two different contracts in their codebase
with similar names (`RoleManager` and `YearnRoleManager`) with different function
signatures. Check which one is actually deployed there:
```bash
cast call 0xb3bd6B2E61753C311EFbCF0111f75D29706D9a41 "getAllocatorFactory()(address)" --rpc-url $ALCHEMY_MAINNET_URL
```
- If this returns an address (even `0x0000...0000`) without reverting, it's
  `YearnRoleManager` and the fork test below should work as-is.
- If it reverts, this address is the older `RoleManager` instead, which doesn't have
  this specific bug (it always uses a single shared allocator, no per-vault factory
  path) — in that case Y3 doesn't apply to this specific deployed instance, and you'd
  need to search Etherscan for a real `YearnRoleManager` deployment to test against
  (paste me the address and I'll adjust the test).

## 8. Run the fork test
```bash
forge test --match-contract Y3_MainnetFork -vvvv
```

This does one of two things depending on live state:
- **If `ALLOCATOR_FACTORY` is already set**: it's read-only — walks every real vault
  under this RoleManager and prints whether its debt allocator's governance is Brain
  (fine) or the vault itself (bricked, bug confirmed live).
- **If `ALLOCATOR_FACTORY` is not set yet**: the bug is dormant. The test proves it
  *would* fire by using `vm.prank` on the real governance address to do something
  that address is already allowed to do (point the RoleManager at a freshly deployed,
  real `DebtAllocatorFactory`, then call `updateDebtAllocator` on one real vault) and
  checks the result. This doesn't send any real transaction to mainnet — it's a local
  fork simulation only.

## What you'll see if it reproduces
Console output listing the real vault address, the resulting allocator address, and
its governance — either confirming Brain has no control over it, or (if already live)
a straight list of every vault's current bricked/not-bricked status.
