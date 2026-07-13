// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockStakingSystem} from "../src/MockStakingSystem.sol";
import {MockDistributor} from "../src/MockDistributor.sol";
import {MockRewardToken} from "../src/MockRewardToken.sol";

interface ISRD {
    function claim(address account) external returns (uint256);
    function reclaim(address account, uint256 idx) external returns (uint256, uint256);
    function sync_rewards(address account) external returns (bool);
}

/// @notice Bounded, ghost-accounting wrapper driving the real, unmodified
/// StakingRewardDistributor.vy through stake/unstake/transfer/claim/reclaim/
/// sync_rewards/time-warp/reward-emission sequences.
contract Handler is Test {
    MockStakingSystem public stakingSystem;
    MockDistributor public distributor;
    MockRewardToken public rewardToken;
    ISRD public srd;

    address[] public actors;

    mapping(address => uint256) public ghostClaimed;

    uint256 public ghostTotalClaimed;
    uint256 public ghostTotalReclaimedToRecipient;
    uint256 public ghostTotalBounty;

    constructor(MockStakingSystem _staking, MockDistributor _distributor, MockRewardToken _rewardToken, address _srd) {
        stakingSystem = _staking;
        distributor = _distributor;
        rewardToken = _rewardToken;
        srd = ISRD(_srd);

        for (uint256 i = 0; i < 4; i++) {
            actors.push(address(uint160(0x2000 + i)));
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
        amount = bound(amount, 1, 1_000_000e18);
        stakingSystem.stake(actor, amount);
    }

    function unstake(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        uint256 bal = stakingSystem.balanceOf(actor);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        stakingSystem.unstake(actor, amount);
    }

    function transferStake(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = stakingSystem.balanceOf(from);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        stakingSystem.transferStake(from, to, amount);
    }

    function setEpochReward(uint256 amount) external {
        amount = bound(amount, 0, 100_000e18);
        distributor.setEpochReward(amount);
    }

    function warp(uint256 numEpochs) external {
        numEpochs = bound(numEpochs, 1, 3);
        vm.warp(block.timestamp + numEpochs * 14 days);
    }

    function syncRewards(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        srd.sync_rewards(actor);
    }

    function claim(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        uint256 claimed = srd.claim(actor);
        ghostClaimed[actor] += claimed;
        ghostTotalClaimed += claimed;
    }

    function reclaim(uint256 actorSeed, uint256 idxSeed) external {
        address actor = _actor(actorSeed);
        // Exercise both the "skip accrued-index reclaim" and bounded-index paths.
        uint256 idx = (idxSeed % 2 == 0) ? type(uint256).max : (idxSeed % 5);

        (uint256 rewards, uint256 bounty) = srd.reclaim(actor, idx);
        ghostTotalReclaimedToRecipient += rewards;
        ghostTotalBounty += bounty;
    }
}
