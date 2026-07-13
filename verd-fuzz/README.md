# Voting Escrow Reward Distributor invariant fuzz harness

Stateful invariant fuzzing against the real, unmodified
`VotingEscrowRewardDistributor.vy` source (deployed at
`0x2548BF65916fdABB5A5673fC4225011FF29ee884` on Ethereum mainnet, in scope). Tracks
migrated veYFI positions with a Curve-style decaying-boost weight (linear slope decay
down to a scheduled full unlock), distinct from the simpler stake/unstake balance
tracking in the other two reward-distributor harnesses in this repo.

Deploys the real Vyper contract (via `VyperDeployer`, requires the `vyper` compiler,
version 0.4.2, on `PATH`) against mock veYFI/distributor/reward-token contracts, then
drives random sequences of `migrate` / `claim` / `reclaim` / `report` (early-exit) /
`sync_rewards` / reward-emission / time-warp calls via a bounded `Handler`, checking
after every call that:

1. **Solvency** - the distributor can never pay out (via `claim` + `reclaim` + reclaim
   bounty + `report` + report bounty, combined) more reward tokens than it has ever
   actually received from the upstream distributor.
2. **Conservation** - every reward token that ever entered the distributor either still
   sits in its balance, or has left via a tracked payout path.

## Run

```bash
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup

pip install vyper==0.4.2   # must be on PATH as `vyper`
vyper --version             # confirm 0.4.2

forge test --match-contract VERDInvariant -v
```

No mainnet RPC needed - this tests the real contract logic in isolation, not live state.

## Result (last run)

1,500 runs x 300 depth (450,000 calls), zero invariant violations, including ~2,000
successful `report()` (early-exit) calls - the narrowest, most unusual code path in
this contract. See `foundry.toml` to adjust `[invariant] runs`/`depth`.

## Note on `targetContract` vs `targetSelector`

`setUp()` calls both `targetContract(address(handler))` **and**
`targetSelector(...)` for the handler's specific entrypoints. `targetContract` is what
actually restricts the invariant fuzzer's target set - without it, Foundry
auto-discovers every contract deployed during `setUp` (including the mocks) and fuzzes
their full raw ABI directly, which let an earlier draft of this harness "manufacture"
reward tokens by calling `MockDistributor` directly and bypassing the real contract
entirely - producing a false failure that had nothing to do with the actual Vyper
source. Keep both calls if you extend this harness.
