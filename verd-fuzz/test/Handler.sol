// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockVeYFI} from "../src/MockVeYFI.sol";
import {MockDistributor} from "../src/MockDistributor.sol";
import {MockRewardToken} from "../src/MockRewardToken.sol";

interface IVERD {
    function epoch() external view returns (uint256);
    function genesis() external view returns (uint256);
    function last_claimed(address account) external view returns (uint256);
    function migrate() external;
    function claim(address account) external returns (uint256);
    function reclaim(address account) external returns (uint256, uint256);
    function report(address account) external returns (uint256, uint256);
    function sync_rewards() external returns (bool);
    function set_snapshot(address account, uint256 amount, uint256 boost, uint256 unlock) external;
    function set_claimer(address account, bool claimer) external;
    function set_reward_expiration(uint256 expiration, uint256 bounty, address recipient) external;
    function set_report_bounty(uint256 bounty, address recipient) external;
    function accept_management() external;
}

/// @notice Bounded, ghost-accounting wrapper driving the real, unmodified
/// VotingEscrowRewardDistributor.vy through migrate/claim/reclaim/report/
/// sync_rewards/reward-emission/time-warp sequences. Acts as `management`
/// itself so it can set snapshots and roles directly.
contract Handler is Test {
    MockVeYFI public veyfi;
    MockDistributor public distributor;
    MockRewardToken public rewardToken;
    IVERD public verd;

    address[] public actors;

    uint256 public ghostTotalClaimed;
    uint256 public ghostTotalReclaimedToRecipient;
    uint256 public ghostTotalReclaimBounty;
    uint256 public ghostTotalReportedToRecipient;
    uint256 public ghostTotalReportBounty;

    constructor(MockVeYFI _veyfi, MockDistributor _distributor, MockRewardToken _rewardToken, address _verd) {
        veyfi = _veyfi;
        distributor = _distributor;
        rewardToken = _rewardToken;
        verd = IVERD(_verd);

        for (uint256 i = 0; i < 4; i++) {
            actors.push(address(uint160(0x3000 + i)));
        }
    }

    function acceptManagement() external {
        verd.accept_management();
    }

    function setUpRoles() external {
        verd.set_claimer(address(this), true);
        verd.set_reward_expiration(2, 1000, address(this));
        verd.set_report_bounty(1000, address(this));
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function setEpochReward(uint256 amount) external {
        amount = bound(amount, 0, 100_000e18);
        distributor.setEpochReward(amount);
    }

    function warp(uint256 numEpochs) external {
        numEpochs = bound(numEpochs, 1, 3);
        vm.warp(block.timestamp + numEpochs * 14 days);
    }

    function migrate(uint256 actorSeed, uint256 amountSeed, uint256 unlockOffsetSeed, uint256 boostExtraSeed) external {
        address actor = _actor(actorSeed);
        if (verd.last_claimed(actor) != 0) return; // already migrated

        uint256 amount = bound(amountSeed, 1e18, 1_000_000e18);
        uint256 current = verd.epoch();
        uint256 unlockEpoch = current + bound(unlockOffsetSeed, 2, 90);
        if (unlockEpoch >= 104) return; // MAX_NUM_EPOCHS guard
        uint256 boost = unlockEpoch + bound(boostExtraSeed, 0, 20);

        uint256 genesisTs = verd.genesis();
        uint256 unlockTimestamp = genesisTs + unlockEpoch * 14 days;

        // Set snapshot as management (this contract), then make the real mock
        // veYFI lock match the snapshot so _check_lock succeeds.
        verd.set_snapshot(actor, amount, boost, unlockTimestamp);
        veyfi.setLock(actor, amount, unlockTimestamp);

        vm.prank(actor);
        verd.migrate();
    }

    function claim(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        uint256 claimed = verd.claim(actor);
        ghostTotalClaimed += claimed;
    }

    function reclaim(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        (uint256 rewards, uint256 bounty) = verd.reclaim(actor);
        ghostTotalReclaimedToRecipient += rewards;
        ghostTotalReclaimBounty += bounty;
    }

    function reportEarlyExit(uint256 actorSeed) external {
        address actor = _actor(actorSeed);
        // Simulate the account's real veYFI lock being withdrawn/reduced early,
        // independent of the distributor's own snapshot of that position.
        veyfi.setLock(actor, 0, 0);

        (uint256 rewards, uint256 bounty) = verd.report(actor);
        ghostTotalReportedToRecipient += rewards;
        ghostTotalReportBounty += bounty;
    }

    function syncRewards() external {
        verd.sync_rewards();
    }
}
