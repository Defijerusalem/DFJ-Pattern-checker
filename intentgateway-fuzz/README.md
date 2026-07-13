# IntentGatewayV2 escrow accounting invariant fuzz harness

Stateful invariant fuzzing against the real, unmodified `IntentGatewayV2.sol` +
`IntentsBase.sol`/`IntrinsicIntents.sol`/`ExtrinsicIntents.sol` source from the
Hyperbridge repo (`evm/src/apps/`), for the HackenProof bug bounty engagement.

Deploys the real contract (behind an `ERC1967Proxy`, matching its real upgradeable
deployment pattern) against a minimal mock host and two mock ERC20 tokens, then
drives random sequences of same-chain `placeOrder` / `fillOrder` (full, partial, and
overpaying-solver variants) / `cancelOrder` calls via a bounded `Handler`, checking
after every call that:

1. **Per-order escrow conservation** - for every `(commitment, token)` pair ever
   touched, the contract's own live escrow ledger (`_orders`) plus everything
   ghost-tracked as released (measured via actual token balance deltas on the
   recipient, not assumed) always equals exactly what was originally escrowed. This
   directly catches over-release (a solver/user extracting more than was ever put in
   for that pair) and under-release (escrow silently reduced without the recipient
   actually being paid the matching amount) in the partial-fill/surplus-split
   arithmetic.
2. **Solvency** - the gateway always holds enough of each token to honor the sum of
   every outstanding escrow entry.

Cross-chain fill/cancel flows (which depend on live ISMP message dispatch/proof
verification) are intentionally out of scope for this harness - same-chain orders
exercise the same escrow/fee/partial-fill/surplus math without needing to mock the
whole ISMP messaging pipeline.

## Run

```bash
forge test --match-contract IntentGatewayInvariant -vv
```

No live RPC needed - this tests the real contract logic in isolation, not on-chain
state. See `foundry.toml` to adjust `[invariant] runs`/`depth`.

## Result (last run)

500 runs x 200 depth (100,000 calls), zero invariant violations across
`invariant_escrowConservationPerOrder` and `invariant_solvency`, including several
hundred genuine full/partial fills and overpay (surplus-split) calls per full
campaign (`Handler` biases order selection toward recently-placed orders so the
fuzzer spends most of its budget on live orders rather than guaranteed no-ops
against already-finalized ones).

## Note on `targetContract` vs `targetSelector`

Same gotcha as the other harnesses in this repo: `setUp()` calls
`targetContract(address(handler))` **and** `targetSelector(...)`. Without
`targetContract`, Foundry auto-discovers every contract deployed during `setUp`
(the mock tokens, the mock host, the real gateway itself) and fuzzes their full raw
ABI directly, bypassing the `Handler`'s bookkeeping entirely.

## Note on Solidity compiler version

The real source requires solc >=0.8.24 (transient-storage `tstore`/`tload` assembly
opcodes were only recognized starting there) and `via_ir = true` (the real
`placeOrder`/`_fillSameChain` functions are too deep in local variables to compile
without it). `foundry.toml` pins `solc = "0.8.24"` as a portable version string for
normal environments with network access to fetch the compiler.
