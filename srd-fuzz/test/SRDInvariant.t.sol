// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {VyperDeployer} from "./VyperDeployer.sol";
import {MockRewardToken} from "../src/MockRewardToken.sol";
import {MockDistributor} from "../src/MockDistributor.sol";
import {MockStakingSystem} from "../src/MockStakingSystem.sol";
import {Handler} from "./Handler.sol";

interface ISRDFull {
    function set_staking(address staking) external;
    function set_depositor(address depositor) external;
    function set_claimer(address account, bool claimer) external;
    function set_reward_expiration(uint256 expiration, uint256 bounty, address recipient) external;
    function set_management(address management) external;
    function accept_management() external;
}

/// @notice Stateful invariant fuzz test against the real, unmodified
/// StakingRewardDistributor.vy source. Drives random sequences of stake/
/// unstake/transfer/claim/reclaim/sync_rewards/reward-emission/time-warp
/// calls and checks that the reward token can never be paid out beyond what
/// the distributor ever actually released to this contract.
contract SRDInvariant is Test {
    VyperDeployer vyperDeployer;
    MockRewardToken rewardToken;
    MockDistributor distributor;
    MockStakingSystem stakingSystem;
    ISRDFull srd;
    address srdAddr;
    Handler handler;

    function setUp() public {
        vyperDeployer = new VyperDeployer();
        rewardToken = new MockRewardToken();
        distributor = new MockDistributor(rewardToken, block.timestamp);

        srdAddr = vyperDeployer.deployContract(
            "vyper/",
            "StakingRewardDistributor",
            abi.encode(address(distributor), address(rewardToken))
        );
        srd = ISRDFull(srdAddr);

        // VyperDeployer was msg.sender during CREATE, so it holds `management`.
        vm.prank(address(vyperDeployer));
        srd.set_management(address(this));
        srd.accept_management();

        stakingSystem = new MockStakingSystem(srdAddr);
        srd.set_staking(address(stakingSystem));
        srd.set_depositor(address(stakingSystem));
        // expiration = 2 epochs (minimum allowed), 10% bounty, recipient = this test contract.
        srd.set_reward_expiration(2, 1000, address(this));

        handler = new Handler(stakingSystem, distributor, rewardToken, srdAddr);
        srd.set_claimer(address(handler), true);

        targetContract(address(handler));
    }

    /// @dev Core "no free money" check: the SRD must never pay out (via claim +
    /// reclaim + reclaim bounty, combined) more reward tokens than it has ever
    /// actually received from the upstream distributor.
    function invariant_solvency() public view {
        assertGe(
            distributor.totalDistributed(),
            handler.ghostTotalClaimed() + handler.ghostTotalReclaimedToRecipient() + handler.ghostTotalBounty(),
            "VULNERABLE: SRD paid out more reward tokens than it ever received from the distributor"
        );
    }

    /// @dev Exact conservation: every token that ever entered the SRD either
    /// still sits in its balance, or has left via claim/reclaim/bounty - no
    /// double counting, nothing silently lost or fabricated.
    function invariant_conservation() public view {
        assertEq(
            rewardToken.balanceOf(srdAddr)
                + handler.ghostTotalClaimed()
                + handler.ghostTotalReclaimedToRecipient()
                + handler.ghostTotalBounty(),
            distributor.totalDistributed(),
            "VULNERABLE: reward token accounting diverged from total ever distributed"
        );
    }

    function invariant_callSummary() public view {
        console2.log("totalDistributed        ", distributor.totalDistributed());
        console2.log("ghostTotalClaimed        ", handler.ghostTotalClaimed());
        console2.log("ghostTotalReclaimedToRecipient", handler.ghostTotalReclaimedToRecipient());
        console2.log("ghostTotalBounty         ", handler.ghostTotalBounty());
        console2.log("srd token balance        ", rewardToken.balanceOf(srdAddr));
    }
}
