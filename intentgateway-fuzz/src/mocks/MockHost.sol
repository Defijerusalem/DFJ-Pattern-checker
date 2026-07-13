// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDispatcher, DispatchPost, DispatchGet} from "@hyperbridge/core/interfaces/IDispatcher.sol";
import {FrozenStatus} from "@hyperbridge/core/libraries/Message.sol";

/// @dev Minimal stand-in for the real IsmpHost. Only same-chain order flows are
/// fuzzed here (placeOrder/fillOrder/cancelOrder for orders whose source ==
/// destination), so `dispatch()` is never actually invoked by the code paths under
/// test - it's stubbed only to satisfy the IDispatcher interface.
contract MockHost is IDispatcher {
    bytes public chainId;
    address public feeTokenAddr;

    constructor(bytes memory chainId_, address feeTokenAddr_) {
        chainId = chainId_;
        feeTokenAddr = feeTokenAddr_;
    }

    function host() external view returns (bytes memory) {
        return chainId;
    }

    function hyperbridge() external pure returns (bytes memory) {
        return bytes("HYPERBRIDGE");
    }

    function frozen() external pure returns (FrozenStatus) {
        return FrozenStatus.None;
    }

    function uniswapV2Router() external pure returns (address) {
        return address(0);
    }

    function nonce() external pure returns (uint256) {
        return 0;
    }

    function feeToken() external view returns (address) {
        return feeTokenAddr;
    }

    function dispatch(DispatchPost memory) external payable returns (bytes32) {
        revert("MockHost: dispatch(Post) not exercised in same-chain fuzzing");
    }

    function dispatch(DispatchGet memory) external payable returns (bytes32) {
        revert("MockHost: dispatch(Get) not exercised in same-chain fuzzing");
    }

    function fundRequest(bytes32, uint256) external payable {
        revert("MockHost: fundRequest not exercised in same-chain fuzzing");
    }
}
