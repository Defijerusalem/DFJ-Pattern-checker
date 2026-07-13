# Staking Reward Distributor invariant fuzz harness

Stateful invariant fuzzing against the real, unmodified `StakingRewardDistributor.vy`
source (deployed at `0x95547ede56cf74b73dd78a37f547127dffda6113` on Ethereum mainnet,
in scope). Unlike the simpler `DelegatedStakingRewardDistributor.vy` tested earlier
(see `../reclaim-poc`), this contract streams rewards linearly within each epoch and
can roll forward across multiple skipped epochs in a single sync - different, more
complex logic that warranted its own dedicated harness rather than reusing the old one.

Deploys the real Vyper contract (via `VyperDeployer`, requires the `vyper` compiler,
version 0.4.2, on `PATH`) against mock staking/distributor/reward-token contracts, then
drives random sequences of `stake` / `unstake` / `transferStake` / `claim` / `reclaim` /
`sync_rewards` / reward-emission / time-warp calls via a bounded `Handler`, checking
after every call that:

1. **Solvency** - the SRD can never pay out (via `claim` + `reclaim` + reclaim bounty,
   combined) more reward tokens than it has ever actually received from the upstream
   distributor.
2. **Conservation** - every reward token that ever entered the SRD either still sits in
   its balance, or has left via `claim`/`reclaim`/bounty - nothing silently lost or
   fabricated.

## Run

```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup

pip install vyper==0.4.2   # must be on PATH as `vyper`
vyper --version             # confirm 0.4.2

forge test --match-contract SRDInvariant -v
```

No mainnet RPC needed - this tests the real contract logic in isolation, not live state.

## Result (last run)

1,500 runs x 300 depth (450,000 calls), zero invariant violations. See `foundry.toml`
to adjust `[invariant] runs`/`depth` for a longer campaign. The revert counts shown per
selector in the summary table (mainly on `reclaim` and `claim`) are expected discards
from bounded-but-imperfect fuzz inputs (e.g. an out-of-range reclaim index), not bugs -
`fail_on_revert = false` correctly treats those as no-ops.
