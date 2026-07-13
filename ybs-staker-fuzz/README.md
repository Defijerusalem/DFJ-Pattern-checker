# YearnBoostedStaker invariant fuzz harness

Stateful invariant fuzzing (not just a manual read) against the real, unmodified
`YearnBoostedStaker.sol` source (deployed at `0xE9A115b77A1057C918F997c32663FdcE24FB873f`
and `0x5D2eA33449A60a70E8FCdc5251FDd86a030fAD91` on Ethereum mainnet, both in scope).

Deploys a fresh copy of the real contract against a `MockERC20`, then drives random
sequences of `stake` / `unstake` / `stakeFor` / `checkpointAccount` / `checkpointGlobal`
/ time-warp calls via a bounded `Handler` contract, checking four invariants after every
call:

1. No actor can ever withdraw more real tokens than they are entitled to.
2. The contract always holds enough underlying tokens to cover `totalSupply`.
3. `totalSupply` always equals the sum of individual account balances.
4. Global staked-minus-unstaked ghost accounting always matches `totalSupply`.

## Run

```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup
forge test --match-contract YearnBoostedStakerInvariant -v
```

No mainnet RPC needed - this tests the real contract logic in isolation, not live state.

## Result (last run)

1,000 runs x 300 depth (300,000 calls per invariant), zero violations, zero reverts
across all six Handler entrypoints. See `foundry.toml` to adjust `[invariant] runs`/`depth`
for a longer campaign.
