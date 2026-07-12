// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {VyperDeployer} from "./VyperDeployer.sol";

import {YearnRoleManager} from "../src/managers/YearnRoleManager.sol";
import {Registry} from "../src/registry/Registry.sol";
import {ReleaseRegistry} from "../src/registry/ReleaseRegistry.sol";
import {DebtAllocator} from "../src/debtAllocators/DebtAllocator.sol";
import {DebtAllocatorFactory} from "../src/debtAllocators/DebtAllocatorFactory.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {IVault} from "../src/interfaces/IVault.sol";
import {IVaultFactory} from "../src/interfaces/IVaultFactory.sol";

/// @notice Reproduces: YearnRoleManager._deployAllocator() initializes new per-vault
/// DebtAllocators with the *vault's own address* as governance, instead of Brain (the
/// address the function's own comment says should be governance). Since the vault
/// contract has no way to ever call back into the allocator on its own, this
/// permanently bricks every onlyGovernance/onlyManagers function on that allocator.
contract Y3_BrickedDebtAllocator is Test {
    address daddy = address(this);
    address brain = address(0xB2A114);
    address security = address(0x5EC0121);
    address keeper = address(0x1CEEEEE);
    address strategyManager = address(0x57A7);

    VyperDeployer vyperDeployer;
    MockERC20 asset;
    IVaultFactory vaultFactory;
    ReleaseRegistry releaseRegistry;
    Registry registry;
    DebtAllocatorFactory debtAllocatorFactory;
    YearnRoleManager roleManager;

    function setUp() public {
        vyperDeployer = new VyperDeployer();
        asset = new MockERC20();

        address vaultOriginal = vyperDeployer.deployContract("vyper/", "VaultV3");
        vaultFactory = IVaultFactory(
            vyperDeployer.deployContract("vyper/", "VaultFactory", abi.encode("Test Factory", vaultOriginal, daddy))
        );

        releaseRegistry = new ReleaseRegistry(daddy);
        // ReleaseRegistry.newRelease requires factory.apiVersion() == tokenizedStrategy.apiVersion();
        // pass the vault factory for both since it already exposes a matching apiVersion().
        releaseRegistry.newRelease(address(vaultFactory), address(vaultFactory));

        registry = new Registry(daddy, "Test Registry", address(releaseRegistry));

        debtAllocatorFactory = new DebtAllocatorFactory();

        roleManager = new YearnRoleManager(
            daddy, // governance
            daddy, // daddy
            brain, // brain
            security,
            keeper,
            strategyManager,
            address(registry)
        );

        registry.setEndorser(address(roleManager), true);

        // Point the role manager at the debt allocator factory - this is the
        // configuration step that activates the buggy per-vault-allocator path.
        roleManager.setPositionHolder(roleManager.ALLOCATOR_FACTORY(), address(debtAllocatorFactory));
    }

    function test_newVaultGetsUnconfigurableDebtAllocator() public {
        address vault = roleManager.newVault(address(asset), 1);

        address debtAllocatorAddr = roleManager.getDebtAllocator(vault);
        DebtAllocator debtAllocator = DebtAllocator(debtAllocatorAddr);

        // The bug: governance ends up being the vault itself, not Brain.
        assertEq(debtAllocator.governance(), vault, "governance should be the vault (the bug)");
        assertTrue(debtAllocator.governance() != brain, "governance is NOT Brain, despite the code's own comment");

        // Brain - the address the comment says should control this allocator -
        // cannot configure it at all.
        vm.prank(brain);
        vm.expectRevert(bytes("!governance"));
        debtAllocator.setManager(brain, true);

        // setStrategyDebtRatio uses onlyManagers (governance OR an added manager) -
        // reverts "!manager", not "!governance". Brain is neither, since only
        // governance can ever call setManager() to add one.
        vm.prank(brain);
        vm.expectRevert(bytes("!manager"));
        debtAllocator.setStrategyDebtRatio(vault, address(0x1234), 5_000);

        vm.prank(brain);
        vm.expectRevert(bytes("!governance"));
        debtAllocator.setPaused(vault, true);

        // Nobody else can either - daddy (overall RoleManager governance) has no
        // special standing on this specific allocator, since its governance was
        // never set to daddy or brain, it was set to `vault`.
        vm.prank(daddy);
        vm.expectRevert(bytes("!governance"));
        debtAllocator.setManager(daddy, true);

        // The only address that could ever pass the `onlyGovernance` check is
        // `vault` itself - and the vault contract has no function that lets it
        // make an outbound call to configure this allocator. The allocator is
        // permanently unconfigurable from the moment it's deployed.
    }
}
