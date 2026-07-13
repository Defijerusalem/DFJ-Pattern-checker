// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {VyperDeployer} from "./VyperDeployer.sol";
import {MockRewardToken} from "../src/MockRewardToken.sol";
import {MockDistributor} from "../src/MockDistributor.sol";
import {MockVeYFI} from "../src/MockVeYFI.sol";
import {Handler} from "./Handler.sol";

interface IVERDFull {
    function set_management(address management) external;
}

/// @notice Stateful invariant fuzz test against the real, unmodified
/// VotingEscrowRewardDistributor.vy source. Drives random sequences of
/// migrate/claim/reclaim/report(early-exit)/sync_rewards/reward-emission/
/// time-warp calls and checks that the reward token can never be paid out
/// beyond what the distributor ever actually released to this contract.
contract VERDInvariant is Test {
    VyperDeployer vyperDeployer;
    MockRewardToken rewardToken;
    MockDistributor distributor;
    MockVeYFI veyfi;
    IVERDFull verd;
    address verdAddr;
    Handler handler;

    function setUp() public {
        vyperDeployer = new VyperDeployer();
        rewardToken = new MockRewardToken();
        veyfi = new MockVeYFI();
        distributor = new MockDistributor(rewardToken, block.timestamp);

        verdAddr = vyperDeployer.deployContract(
            "vyper/",
            "VotingEscrowRewardDistributor",
            abi.encode(address(distributor), address(rewardToken), address(veyfi))
        );
        verd = IVERDFull(verdAddr);

        // VyperDeployer was msg.sender during CREATE, so it holds `management`.
        // Hand management straight to the Handler, which needs it to set
        // snapshots and roles itself.
        handler = new Handler(veyfi, distributor, rewardToken, verdAddr);

        vm.prank(address(vyperDeployer));
        verd.set_management(address(handler));
        handler.acceptManagement();
        handler.setUpRoles();

        // IMPORTANT: targetContract() is what actually restricts the invariant
        // fuzzer to this address - targetSelector() alone does NOT exclude other
        // deployed contracts (MockDistributor, MockRewardToken, MockVeYFI) from
        // being auto-discovered and fuzzed directly with their full raw ABI,
        // which would let the fuzzer manufacture reward tokens completely
        // bypassing the real contract under test.
        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = Handler.setEpochReward.selector;
        selectors[1] = Handler.warp.selector;
        selectors[2] = Handler.migrate.selector;
        selectors[3] = Handler.claim.selector;
        selectors[4] = Handler.reclaim.selector;
        selectors[5] = Handler.reportEarlyExit.selector;
        selectors[6] = Handler.syncRewards.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @dev Core "no free money" check: the VERD must never pay out (via claim
    /// + reclaim + reclaim bounty + report + report bounty, combined) more
    /// reward tokens than it has ever actually received from the upstream
    /// distributor.
    function invariant_solvency() public view {
        assertGe(
            distributor.totalDistributed(),
            handler.ghostTotalClaimed()
                + handler.ghostTotalReclaimedToRecipient()
                + handler.ghostTotalReclaimBounty()
                + handler.ghostTotalReportedToRecipient()
                + handler.ghostTotalReportBounty(),
            "VULNERABLE: VERD paid out more reward tokens than it ever received from the distributor"
        );
    }

    /// @dev Exact conservation: every token that ever entered the VERD either
    /// still sits in its balance, or has left via claim/reclaim/report/bounty.
    function invariant_conservation() public view {
        assertEq(
            rewardToken.balanceOf(verdAddr)
                + handler.ghostTotalClaimed()
                + handler.ghostTotalReclaimedToRecipient()
                + handler.ghostTotalReclaimBounty()
                + handler.ghostTotalReportedToRecipient()
                + handler.ghostTotalReportBounty(),
            distributor.totalDistributed(),
            "VULNERABLE: reward token accounting diverged from total ever distributed"
        );
    }

    function invariant_callSummary() public view {
        console2.log("totalDistributed  ", distributor.totalDistributed());
        console2.log("ghostTotalClaimed ", handler.ghostTotalClaimed());
        console2.log("reclaimedToRecipient", handler.ghostTotalReclaimedToRecipient());
        console2.log("reclaimBounty     ", handler.ghostTotalReclaimBounty());
        console2.log("reportedToRecipient", handler.ghostTotalReportedToRecipient());
        console2.log("reportBounty      ", handler.ghostTotalReportBounty());
        console2.log("verd token balance", rewardToken.balanceOf(verdAddr));
    }
}
