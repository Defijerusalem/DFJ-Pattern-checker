# Locker/Operator race-condition mint PoC (Yield Basis liquid locker)

Proves: an attacker with only a dust-value veYB position can capture yYB tokens
minted for value **another party** deposited into the Locker's lock, via a race
condition between `escrow.increase_amount()` (permissionlessly callable by anyone,
bypassing `Locker.sol`'s own access control entirely) and
`Operator.nftTransferCallback()` (which mints `real balance - cached balance` to
whoever triggers the *next* NFT transfer into the Locker, regardless of who
actually grew the real balance).

Targets real, currently-deployed mainnet contracts:
- `Locker`: `0x0000000C90799449af8eE0B240Da639144a36C6A`
- `Operator`: `0x1111111Ecd5Ae05422aeCe517072ec33Dbf34af9`
- `escrow` and `yToken` addresses are read live from the above at fork time, not
  hardcoded, so the test can't accidentally point at the wrong contract.

## Setup (same as before if you still have Foundry from the Y3 PoC)

```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
```

## Run

Needs a mainnet RPC (same Alchemy Secret as before, `ALCHEMY_MAINNET_URL`):

```bash
forge test --match-contract LockerRaceMint -vvvv
```

## What you should see

Console output showing:
1. `cachedLockedAmount` and real `getLockedAmount()` starting in sync.
2. After the "victim" account calls `escrow.increase_amount()` directly (bypassing
   Locker/Operator entirely) — real balance jumps, cache stays stale.
3. The "attacker" account creates a dust-value lock, toggles it to match the
   Locker's infinite-lock status, and transfers it into the Locker.
4. The assertion `minted > victimDeposit` should hold — the attacker, who only
   contributed a dust-value lock, receives yToken minted for the victim's entire
   multi-million-token deposit.

If the final `assertEq(cachedLockedAmount, getLockedAmount())` and the `minted >
victimDeposit` assertions both pass, the exploit is confirmed against live mainnet
state, not a hypothetical.

## Note on realism

The "victim" step (a direct call to `escrow.increase_amount()`) doesn't require any
special privilege or mistake — it's a plain, permissionless function on a
separately-deployed, publicly-callable contract. Anything that ever calls it
outside of `Operator.lock()`'s own atomic pattern creates the exploitable window;
this PoC's "victim" is a stand-in for that general case, not a specific integration
bug elsewhere.
