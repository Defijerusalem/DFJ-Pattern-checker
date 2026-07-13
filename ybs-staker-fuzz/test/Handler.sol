// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {YearnBoostedStaker} from "../src/YearnBoostedStaker.sol";
import {MockERC20} from "../src/MockERC20.sol";

/// @notice Bounded, ghost-accounting wrapper around YearnBoostedStaker's real,
/// unmodified stake/unstake/checkpoint/time-warp entrypoints, used to drive
/// Foundry's stateful invariant fuzzer.
contract Handler is Test {
    YearnBoostedStaker public staker;
    MockERC20 public token;

    address[] public actors;

    // Ghost accounting: cumulative real token amounts staked/unstaked per actor.
    mapping(address => uint256) public ghostStaked;
    mapping(address => uint256) public ghostUnstaked;

    uint256 public ghostTotalStaked;
    uint256 public ghostTotalUnstaked;

    constructor(YearnBoostedStaker _staker, MockERC20 _token) {
        staker = _staker;
        token = _token;

        for (uint256 i = 0; i < 4; i++) {
            address actor = address(uint160(0x1000 + i));
            actors.push(actor);
            token.mint(actor, 1_000_000_000e18);
            vm.prank(actor);
            token.approve(address(staker), type(uint256).max);
        }
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function stake(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        amount = bound(amount, 2, 1_000_000e18);
        if (token.balanceOf(actor) < amount) return;

        vm.prank(actor);
        uint256 staked = staker.stake(amount);

        ghostStaked[actor] += staked;
        ghostTotalStaked += staked;
    }

    function stakeFor(uint256 actorSeed, uint256 targetSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        address target = _actor(targetSeed);

        // Grant approval so this path is actually exercised (not just reverting).
        vm.prank(target);
        staker.setApprovedCaller(actor, YearnBoostedStaker.ApprovalStatus.StakeAndUnstake);

        amount = bound(amount, 2, 1_000_000e18);
        if (token.balanceOf(actor) < amount) return;

        vm.prank(actor);
        uint256 staked = staker.stakeFor(target, amount);

        // Actor pays, but `target`'s balance is what actually grows and is what
        // `target` becomes entitled to withdraw - credit the ghost accounting
        // to `target` so the per-actor "can't extract more than owned" invariant
        // stays meaningful for this path.
        ghostStaked[target] += staked;
        ghostTotalStaked += staked;
    }

    function unstake(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        uint256 bal = staker.balanceOf(actor);
        if (bal < 2) return;
        amount = bound(amount, 2, bal);

        vm.prank(actor);
        uint256 unstaked = staker.unstake(amount, actor);

        ghostUnstaked[actor] += unstaked;
        ghostTotalUnstaked += unstaked;
    }

    function warp(uint256 numWeeks) external {
        numWeeks = bound(numWeeks, 1, 3);
        vm.warp(block.timestamp + numWeeks * 1 weeks);
    }

    function checkpoint(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        staker.checkpointAccount(actor);
    }

    function checkpointGlobal() external {
        staker.checkpointGlobal();
    }
}
