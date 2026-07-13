// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MockRewardToken} from "./MockRewardToken.sol";

/// @notice Stand-in for the real upstream IDistributor. Mints a controllable
/// amount of the real reward token to whoever calls claim() (the SRD), and
/// tracks the running total ever released for conservation checks.
contract MockDistributor {
    MockRewardToken public immutable rewardToken;
    uint256 public immutable genesisTime;
    uint256 public epochRewardAmount;
    uint256 public totalDistributed;

    constructor(MockRewardToken _rewardToken, uint256 _genesis) {
        rewardToken = _rewardToken;
        genesisTime = _genesis;
    }

    function genesis() external view returns (uint256) {
        return genesisTime;
    }

    function setEpochReward(uint256 amount) external {
        epochRewardAmount = amount;
    }

    function claim() external returns (uint256, uint256, uint256) {
        uint256 amount = epochRewardAmount;
        if (amount > 0) {
            rewardToken.mint(msg.sender, amount);
            totalDistributed += amount;
        }
        return (0, 0, amount);
    }
}
