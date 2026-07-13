// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @notice Stand-in for the real veYFI VotingEscrow. Lets the test harness
/// freely set (and later reduce, to simulate an early exit/withdrawal) an
/// account's real locked amount/end time, independent of the distributor's
/// own snapshot of that position.
contract MockVeYFI {
    mapping(address => uint256) public lockedAmount;
    mapping(address => uint256) public lockedEnd;

    function locked(address account) external view returns (uint256, uint256) {
        return (lockedAmount[account], lockedEnd[account]);
    }

    function setLock(address account, uint256 amount, uint256 end) external {
        lockedAmount[account] = amount;
        lockedEnd[account] = end;
    }
}
