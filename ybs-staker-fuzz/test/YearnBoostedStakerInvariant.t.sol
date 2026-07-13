// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test, console2} from "forge-std/Test.sol";
import {YearnBoostedStaker} from "../src/YearnBoostedStaker.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {Handler} from "./Handler.sol";

/// @notice Stateful invariant fuzz test against the real, unmodified YearnBoostedStaker
/// source. Drives random sequences of stake/unstake/stakeFor/checkpoint/time-warp calls
/// via the Handler and checks that core economic invariants never break:
///   1. No actor can ever withdraw more real tokens than they are entitled to.
///   2. The contract always holds enough underlying tokens to cover totalSupply.
///   3. totalSupply always equals the sum of individual balances.
///   4. Global staked-minus-unstaked ghost accounting always matches totalSupply.
contract YearnBoostedStakerInvariant is Test {
    YearnBoostedStaker staker;
    MockERC20 token;
    Handler handler;

    function setUp() public {
        token = new MockERC20();
        // Real, unmodified YearnBoostedStaker constructor: 7-week max growth,
        // start_time = 0 (defaults to block.timestamp), owner = this test contract.
        staker = new YearnBoostedStaker(address(token), 7, 0, address(this));
        handler = new Handler(staker, token);

        targetContract(address(handler));
    }

    /// @dev Core "no free money" check: no actor should ever be able to withdraw
    /// (in real token terms) more than they are actually entitled to.
    function invariant_noActorExtractsMoreThanOwned() public view {
        uint256 nActors = handler.actorsLength();
        for (uint256 i = 0; i < nActors; i++) {
            address actor = handler.actors(i);
            assertLe(
                handler.ghostUnstaked(actor),
                handler.ghostStaked(actor),
                "VULNERABLE: actor extracted more real tokens than they were ever entitled to"
            );
        }
    }

    /// @dev The contract must always hold enough underlying tokens to cover totalSupply.
    function invariant_solvency() public view {
        assertGe(
            token.balanceOf(address(staker)),
            staker.totalSupply(),
            "VULNERABLE: staker is insolvent - totalSupply exceeds real token balance held"
        );
    }

    /// @dev totalSupply should equal the sum of all individual account balances.
    function invariant_totalSupplyMatchesSumOfBalances() public view {
        uint256 nActors = handler.actorsLength();
        uint256 sum;
        for (uint256 i = 0; i < nActors; i++) {
            sum += staker.balanceOf(handler.actors(i));
        }
        assertEq(
            staker.totalSupply(),
            sum,
            "VULNERABLE: totalSupply diverged from the sum of individual account balances"
        );
    }

    /// @dev Global conservation: total ever staked minus total ever unstaked equals
    /// the contract's current totalSupply.
    function invariant_globalConservation() public view {
        assertEq(
            handler.ghostTotalStaked() - handler.ghostTotalUnstaked(),
            staker.totalSupply(),
            "VULNERABLE: global stake/unstake accounting diverged from totalSupply"
        );
    }

    function invariant_callSummary() public view {
        console2.log("ghostTotalStaked  ", handler.ghostTotalStaked());
        console2.log("ghostTotalUnstaked", handler.ghostTotalUnstaked());
        console2.log("totalSupply       ", staker.totalSupply());
    }
}
