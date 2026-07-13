// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IntentGatewayV2} from "../src/apps/IntentGatewayV2.sol";
import {
    Order,
    TokenInfo,
    PaymentInfo,
    DispatchInfo,
    FillOptions,
    CancelOptions
} from "../src/hyperbridge/core/apps/IntentGatewayV2.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @notice Drives placeOrder/fillOrder/cancelOrder for SAME-CHAIN orders only
/// (source == destination) against the real, unmodified IntentGatewayV2 +
/// IntrinsicIntents same-chain fill/cancel logic. Cross-chain flows depend on
/// live ISMP messaging and aren't self-contained enough to fuzz meaningfully
/// here; the same-chain path is where all the partial-fill / surplus-split /
/// protocol-fee arithmetic actually lives.
contract Handler is Test {
    IntentGatewayV2 public gateway;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    bytes public CHAIN_ID;

    address[3] public actors;

    struct Placed {
        Order order;
        bytes32 commitment;
    }

    Placed[] public placedOrders;

    // ghost accounting: commitment => token => amount, checked against the
    // real, unmodified contract's own escrow ledger (`_orders`) in the
    // invariant test.
    mapping(bytes32 => mapping(address => uint256)) public ghostOriginalEscrow;
    mapping(bytes32 => mapping(address => uint256)) public ghostReleased;
    // every (commitment, token) pair ever touched, for invariant iteration
    bytes32[] public knownCommitments;
    address[] public knownTokensForCommitment_flat; // parallel index-matched w/ below
    mapping(bytes32 => address[]) public tokensForCommitment;
    mapping(bytes32 => mapping(address => bool)) internal _tokenSeenForCommitment;

    uint256 public callsPlaceOrder;
    uint256 public callsFillFull;
    uint256 public callsFillPartial;
    uint256 public callsCancel;

    constructor(IntentGatewayV2 gateway_, MockERC20 tokenA_, MockERC20 tokenB_, bytes memory chainId_) {
        gateway = gateway_;
        tokenA = tokenA_;
        tokenB = tokenB_;
        CHAIN_ID = chainId_;

        actors[0] = address(0xA11CE);
        actors[1] = address(0xB0B);
        actors[2] = address(0xC0FFEE);

        for (uint256 i = 0; i < 3; i++) {
            tokenA.mint(actors[i], 1_000_000e18);
            tokenB.mint(actors[i], 1_000_000e18);
            vm.prank(actors[i]);
            tokenA.approve(address(gateway), type(uint256).max);
            vm.prank(actors[i]);
            tokenB.approve(address(gateway), type(uint256).max);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % 3];
    }

    /// @dev Biases order selection toward the most recently placed orders, since
    /// uniform selection over the whole history mostly picks orders that are
    /// already filled/cancelled (a guaranteed no-op), starving the fuzzer of
    /// real fill/cancel coverage.
    function _recentOrderIndex(uint256 seed) internal view returns (uint256) {
        uint256 len = placedOrders.length;
        uint256 window = len > 8 ? 8 : len;
        uint256 start = len - window;
        return start + (seed % window);
    }

    function _token(uint256 seed) internal view returns (MockERC20) {
        return seed % 2 == 0 ? tokenA : tokenB;
    }

    function _recordToken(bytes32 commitment, address token) internal {
        if (!_tokenSeenForCommitment[commitment][token]) {
            _tokenSeenForCommitment[commitment][token] = true;
            tokensForCommitment[commitment].push(token);
        }
    }

    function knownCommitmentsLength() external view returns (uint256) {
        return knownCommitments.length;
    }

    function tokensForCommitmentLength(bytes32 commitment) external view returns (uint256) {
        return tokensForCommitment[commitment].length;
    }

    /// @dev Places a same-chain order with 1-2 distinct input/output token legs.
    function placeOrder(
        uint256 actorSeed,
        uint256 numLegsSeed,
        uint256 amountSeed0,
        uint256 amountSeed1,
        uint256 deadlineSeed
    ) external {
        address user = _actor(actorSeed);
        uint256 numLegs = bound(numLegsSeed, 1, 2);

        TokenInfo[] memory inputs = new TokenInfo[](numLegs);
        TokenInfo[] memory outputs = new TokenInfo[](numLegs);

        uint256[] memory amountSeeds = new uint256[](2);
        amountSeeds[0] = amountSeed0;
        amountSeeds[1] = amountSeed1;

        if (numLegs == 1) {
            MockERC20 tok = _token(actorSeed);
            uint256 amt = bound(amountSeeds[0], 1, 1_000e18);
            if (tok.balanceOf(user) < amt) return;
            inputs[0] = TokenInfo({token: bytes32(uint256(uint160(address(tok)))), amount: amt});
            outputs[0] = TokenInfo({token: bytes32(uint256(uint160(address(tok)))), amount: bound(amountSeeds[1], 1, 1_000e18)});
        } else {
            uint256 amtA = bound(amountSeeds[0], 1, 1_000e18);
            uint256 amtB = bound(amountSeeds[1], 1, 1_000e18);
            if (tokenA.balanceOf(user) < amtA || tokenB.balanceOf(user) < amtB) return;
            inputs[0] = TokenInfo({token: bytes32(uint256(uint160(address(tokenA)))), amount: amtA});
            inputs[1] = TokenInfo({token: bytes32(uint256(uint160(address(tokenB)))), amount: amtB});
            // deliberately different output amounts so the output side isn't
            // just a mirror of the input side
            outputs[0] = TokenInfo({token: bytes32(uint256(uint160(address(tokenA)))), amount: bound(amtB, 1, 1_000e18)});
            outputs[1] = TokenInfo({token: bytes32(uint256(uint160(address(tokenB)))), amount: bound(amtA, 1, 1_000e18)});
        }

        Order memory order;
        order.destination = CHAIN_ID; // must match host() for same-chain routing
        order.deadline = block.number + bound(deadlineSeed, 1, 5_000_000);
        order.fees = 0;
        order.session = address(0);
        order.predispatch = DispatchInfo({assets: new TokenInfo[](0), call: ""});
        order.inputs = inputs;
        order.output = PaymentInfo({beneficiary: bytes32(uint256(uint160(user))), assets: outputs, call: ""});

        uint256 nonceBefore = gateway._nonce();

        vm.prank(user);
        try gateway.placeOrder{value: 0}(order, bytes32(0)) {
            // reconstruct exactly what the contract hashed as the commitment
            Order memory stored = order;
            stored.user = bytes32(uint256(uint160(user)));
            stored.source = CHAIN_ID;
            stored.nonce = nonceBefore;
            bytes32 commitment = keccak256(abi.encode(stored));

            placedOrders.push(Placed({order: stored, commitment: commitment}));
            knownCommitments.push(commitment);

            for (uint256 i = 0; i < inputs.length; i++) {
                address tok = address(uint160(uint256(inputs[i].token)));
                uint256 escrowed = gateway._orders(commitment, tok);
                ghostOriginalEscrow[commitment][tok] += escrowed;
                _recordToken(commitment, tok);
            }
            callsPlaceOrder++;
        } catch {
            // reverted (e.g. InvalidInput from duplicate token, insufficient balance edge case) - fine, skip
        }
    }

    /// @dev Attempts to fill an already-placed, not-yet-finalized order. Randomly
    /// chooses full vs partial payment, and sometimes overpays to exercise the
    /// surplus-split path.
    function fillOrder(uint256 orderIndexSeed, uint256 solverSeed, uint256 payFractionSeed, uint256 overpaySeed)
        external
    {
        if (placedOrders.length == 0) return;
        Placed storage p = placedOrders[_recentOrderIndex(orderIndexSeed)];
        Order memory order = p.order;
        bytes32 commitment = p.commitment;

        if (gateway._filled(commitment) != address(0)) return;
        if (order.deadline < block.number) return;

        address solver = _actor(solverSeed);

        uint256 len = order.output.assets.length;
        FillOptions memory options;
        options.relayerFee = 0;
        options.nativeDispatchFee = 0;
        options.outputs = new TokenInfo[](len);

        bool full = (payFractionSeed % 2 == 0);
        for (uint256 i = 0; i < len; i++) {
            address outToken = address(uint160(uint256(order.output.assets[i].token)));
            uint256 required = order.output.assets[i].amount;
            uint256 payAmount;
            if (full) {
                bool overpay = (overpaySeed % 3 == 0);
                payAmount = overpay ? required + bound(overpaySeed, 1, 100e18) : required;
            } else {
                payAmount = bound(payFractionSeed + i, 1, required);
            }
            if (MockERC20(outToken).balanceOf(solver) < payAmount) return;
            options.outputs[i] = TokenInfo({token: order.output.assets[i].token, amount: payAmount});
        }

        // snapshot escrow + solver balances for every input token before the call
        uint256 inputsLen = order.inputs.length;
        uint256[] memory escrowBefore = new uint256[](inputsLen);
        uint256[] memory solverBalBefore = new uint256[](inputsLen);
        for (uint256 i = 0; i < inputsLen; i++) {
            address inTok = address(uint160(uint256(order.inputs[i].token)));
            escrowBefore[i] = gateway._orders(commitment, inTok);
            solverBalBefore[i] = MockERC20(inTok).balanceOf(solver);
        }

        vm.prank(solver);
        try gateway.fillOrder(order, options) {
            for (uint256 i = 0; i < inputsLen; i++) {
                address inTok = address(uint160(uint256(order.inputs[i].token)));
                uint256 escrowAfter = gateway._orders(commitment, inTok);
                uint256 solverBalAfter = MockERC20(inTok).balanceOf(solver);

                uint256 released = escrowBefore[i] - escrowAfter; // reverts (caught by try) if it'd underflow
                uint256 received = solverBalAfter - solverBalBefore[i];

                // the amount released from escrow for this token must exactly
                // match what the solver actually received for it
                assertEq(released, received, "MISMATCH: escrow release != solver's actual token receipt");

                ghostReleased[commitment][inTok] += released;
                _recordToken(commitment, inTok);
            }
            if (full) callsFillFull++;
            else callsFillPartial++;
        } catch {
            // legitimate revert (PartialFillNotAllowed, Expired, InvalidInput, etc.)
        }
    }

    /// @dev Cancels a same-chain order (only the original user may do so).
    function cancelOrder(uint256 orderIndexSeed) external {
        if (placedOrders.length == 0) return;
        Placed storage p = placedOrders[_recentOrderIndex(orderIndexSeed)];
        Order memory order = p.order;
        bytes32 commitment = p.commitment;

        if (gateway._filled(commitment) != address(0)) return;
        address user = address(uint160(uint256(order.user)));

        uint256 inputsLen = order.inputs.length;
        uint256[] memory escrowBefore = new uint256[](inputsLen);
        uint256[] memory userBalBefore = new uint256[](inputsLen);
        for (uint256 i = 0; i < inputsLen; i++) {
            address inTok = address(uint160(uint256(order.inputs[i].token)));
            escrowBefore[i] = gateway._orders(commitment, inTok);
            userBalBefore[i] = MockERC20(inTok).balanceOf(user);
        }

        CancelOptions memory options;
        options.relayerFee = 0;
        options.height = 0;

        vm.prank(user);
        try gateway.cancelOrder(order, options) {
            for (uint256 i = 0; i < inputsLen; i++) {
                address inTok = address(uint160(uint256(order.inputs[i].token)));
                uint256 escrowAfter = gateway._orders(commitment, inTok);
                uint256 userBalAfter = MockERC20(inTok).balanceOf(user);

                uint256 released = escrowBefore[i] - escrowAfter;
                uint256 received = userBalAfter - userBalBefore[i];

                assertEq(released, received, "MISMATCH: cancel refund != user's actual token receipt");

                ghostReleased[commitment][inTok] += released;
                _recordToken(commitment, inTok);
            }
            callsCancel++;
        } catch {
            // legitimate revert (NotExpired/Unauthorized/UnknownOrder etc.)
        }
    }

    function warp(uint256 seed) external {
        vm.roll(block.number + bound(seed, 1, 50));
    }
}
