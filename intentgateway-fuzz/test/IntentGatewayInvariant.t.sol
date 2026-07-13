// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IntentGatewayV2} from "../src/apps/IntentGatewayV2.sol";
import {Params} from "../src/hyperbridge/core/apps/IntentGatewayV2.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockHost} from "../src/mocks/MockHost.sol";
import {Handler} from "./Handler.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Stateful invariant fuzz test against the real, unmodified
/// IntentGatewayV2 + IntentsBase/IntrinsicIntents/ExtrinsicIntents source
/// (evm/src/apps/*). Drives random sequences of same-chain placeOrder/
/// fillOrder(full+partial+overpay)/cancelOrder calls and checks that the
/// escrow ledger the contract maintains internally (`_orders`) can never be
/// drained by more than what was ever actually escrowed for that
/// (commitment, token) pair, and that the contract always holds enough
/// real token balance to honor every order it still thinks is outstanding.
contract IntentGatewayInvariant is Test {
    IntentGatewayV2 gateway;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockHost host;
    Handler handler;

    bytes constant CHAIN_ID = bytes("EVM-1");

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");

        IntentGatewayV2 impl = new IntentGatewayV2(address(this));
        host = new MockHost(CHAIN_ID, address(tokenA));

        Params memory p = Params({
            host: address(host),
            dispatcher: address(host),
            solverSelection: false,
            surplusShareBps: 5000,
            protocolFeeBps: 0,
            priceOracle: address(0)
        });
        bytes[] memory peers = new bytes[](0);
        bytes memory initData = abi.encodeCall(IntentGatewayV2.initialize, (p, peers));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        gateway = IntentGatewayV2(payable(address(proxy)));

        handler = new Handler(gateway, tokenA, tokenB, CHAIN_ID);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = Handler.placeOrder.selector;
        selectors[1] = Handler.fillOrder.selector;
        selectors[2] = Handler.cancelOrder.selector;
        selectors[3] = Handler.warp.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev For every (commitment, token) pair the handler has ever touched,
    /// the contract's own live escrow ledger plus everything ghost-tracked as
    /// released must equal exactly what was originally escrowed. If a bug let
    /// a solver/user pull out more than was ever put in for that pair, this
    /// breaks (released > original, so escrow underflows first - caught
    /// separately by the try/catch's absence of a MISMATCH assert failure
    /// having fired, OR - if a bug lets the maths track escrow going down
    /// without the recipient actually getting paid the same amount - the
    /// MISMATCH assert inside the handler itself fires first).
    function invariant_escrowConservationPerOrder() public view {
        uint256 n = handler.knownCommitmentsLength();
        for (uint256 i = 0; i < n; i++) {
            bytes32 commitment = handler.knownCommitments(i);
            uint256 tlen = handler.tokensForCommitmentLength(commitment);
            for (uint256 j = 0; j < tlen; j++) {
                address token = handler.tokensForCommitment(commitment, j);
                uint256 original = handler.ghostOriginalEscrow(commitment, token);
                uint256 released = handler.ghostReleased(commitment, token);
                uint256 remaining = gateway._orders(commitment, token);
                assertEq(
                    remaining + released,
                    original,
                    "VULNERABLE: per-order escrow conservation broken (over- or under-release)"
                );
            }
        }
    }

    /// @dev Solvency: the gateway must always hold enough of each token to
    /// honor the sum of all outstanding (non-zero) escrow entries for it.
    function invariant_solvency() public view {
        uint256 n = handler.knownCommitmentsLength();
        uint256 outstandingA;
        uint256 outstandingB;
        for (uint256 i = 0; i < n; i++) {
            bytes32 commitment = handler.knownCommitments(i);
            outstandingA += gateway._orders(commitment, address(tokenA));
            outstandingB += gateway._orders(commitment, address(tokenB));
        }
        assertGe(tokenA.balanceOf(address(gateway)), outstandingA, "VULNERABLE: gateway insolvent for tokenA");
        assertGe(tokenB.balanceOf(address(gateway)), outstandingB, "VULNERABLE: gateway insolvent for tokenB");
    }

    function invariant_callSummary() public view {
        console2.log("placeOrder calls   ", handler.callsPlaceOrder());
        console2.log("fillOrder full      ", handler.callsFillFull());
        console2.log("fillOrder partial   ", handler.callsFillPartial());
        console2.log("cancelOrder calls   ", handler.callsCancel());
        console2.log("known commitments   ", handler.knownCommitmentsLength());
        console2.log("gateway tokenA bal  ", tokenA.balanceOf(address(gateway)));
        console2.log("gateway tokenB bal  ", tokenB.balanceOf(address(gateway)));
    }
}
