// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {DebtAllocator} from "../src/debtAllocators/DebtAllocator.sol";
import {DebtAllocatorFactory} from "../src/debtAllocators/DebtAllocatorFactory.sol";

interface IYearnRoleManagerLike {
    function getAllocatorFactory() external view returns (address);
    function getDebtAllocator(address vault) external view returns (address);
    function getBrain() external view returns (address);
    function governance() external view returns (address); // Governance2Step exposes this directly
    function getAllVaults() external view returns (address[] memory);
    function updateDebtAllocator(address vault) external returns (address);
}

/// @notice Mainnet-fork check for Y3: does the real, live YearnRoleManager have
/// ALLOCATOR_FACTORY set (meaning the buggy per-vault-allocator path is already
/// active), and if so, are any of its real vaults already carrying a bricked
/// DebtAllocator (governance == the vault itself instead of Brain)?
///
/// This is read-only against real state where possible. Where it needs to prove the
/// *code path* fires (not just check existing state), it uses vm.prank on the real,
/// already-privileged governance address to call a function that address is already
/// allowed to call - no forged capability, same principle as the Y2 fork test.
contract Y3_MainnetFork is Test {
    // From vault-periphery/scripts/DeployTimelock.s.sol - Yearn's own mainnet config.
    // NOTE: verify this is actually a YearnRoleManager and not the older RoleManager
    // before trusting results - see REPLIT_Y3.md for how to check.
    address constant ROLE_MANAGER = 0xb3bd6B2E61753C311EFbCF0111f75D29706D9a41;

    IYearnRoleManagerLike roleManager;

    function setUp() public {
        string memory rpc = vm.envString("ALCHEMY_MAINNET_URL");
        vm.createSelectFork(rpc);
        roleManager = IYearnRoleManagerLike(ROLE_MANAGER);
    }

    function test_checkIfAllocatorFactoryPathIsLive() public {
        address factory = roleManager.getAllocatorFactory();
        address brain = roleManager.getBrain();
        address governance = roleManager.governance();

        console2.log("RoleManager:      ", ROLE_MANAGER);
        console2.log("ALLOCATOR_FACTORY:", factory);
        console2.log("Brain:            ", brain);
        console2.log("Governance:       ", governance);

        if (factory == address(0)) {
            console2.log("ALLOCATOR_FACTORY is NOT set yet - the buggy path is dormant, not active.");
            console2.log("Proving it WOULD fire if activated, via a real governance call:");

            // Deploy a fresh, real DebtAllocatorFactory - anyone can do this permissionlessly,
            // it doesn't need to be an "official" one.
            DebtAllocatorFactory freshFactory = new DebtAllocatorFactory();

            // The real governance address doing something it is already allowed to do:
            // pointing its own RoleManager at a (freshly deployed, but real) factory.
            vm.prank(governance);
            (bool ok, ) = address(roleManager).call(
                abi.encodeWithSignature("setPositionHolder(bytes32,address)", keccak256("Allocator Factory"), address(freshFactory))
            );
            require(ok, "setPositionHolder failed - governance address or ABI may be wrong, see REPLIT_Y3.md");

            address[] memory vaults = roleManager.getAllVaults();
            require(vaults.length > 0, "no vaults registered under this RoleManager");
            address vault = vaults[0];

            vm.prank(governance);
            address newAllocator = roleManager.updateDebtAllocator(vault);

            address actualGovernance = DebtAllocator(newAllocator).governance();
            console2.log("New allocator governance ended up as:", actualGovernance);
            console2.log("Vault address was:                   ", vault);
            console2.log("Brain address is:                    ", brain);

            assertEq(actualGovernance, vault, "bug not reproduced - governance did not become the vault address");
            assertTrue(actualGovernance != brain, "governance should NOT be Brain if the bug is present");
        } else {
            console2.log("ALLOCATOR_FACTORY is ALREADY set - checking existing vaults for bricked allocators:");
            address[] memory vaults = roleManager.getAllVaults();
            for (uint256 i = 0; i < vaults.length; i++) {
                address allocator = roleManager.getDebtAllocator(vaults[i]);
                if (allocator == address(0)) continue;
                address gov = DebtAllocator(allocator).governance();
                console2.log("vault:", vaults[i]);
                console2.log("  allocator:", allocator);
                console2.log("  governance:", gov);
                if (gov == vaults[i]) {
                    console2.log("  ^ BRICKED: governance is the vault itself, not Brain");
                }
            }
        }
    }
}
