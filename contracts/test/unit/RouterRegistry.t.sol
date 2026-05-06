// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RouterRegistry} from "../../src/RouterRegistry.sol";

contract RouterRegistryTest is Test {
    RouterRegistry registry;
    address constant OWNER = address(0xA11CE);
    address constant ATTACKER = address(0xBAD);
    bytes32 constant ROUTER_ID = bytes32("router-1");
    bytes32 constant CATALOG_HASH = keccak256("router-1/catalog/v1");
    bytes32 constant PRICING_HASH = keccak256("router-1/pricing/v1");

    function setUp() public {
        registry = new RouterRegistry();
        vm.deal(OWNER, 10 ether);
    }

    function test_registerRouter_storesOwnerAndHashes() public {
        vm.prank(OWNER);
        registry.registerRouter{value: 1 ether}(ROUTER_ID, CATALOG_HASH, PRICING_HASH);
        (address owner, bool active, bytes32 catalogHash, bytes32 pricingHash, uint256 bond) =
            registry.routers(ROUTER_ID);
        assertEq(owner, OWNER);
        assertTrue(active);
        assertEq(catalogHash, CATALOG_HASH);
        assertEq(pricingHash, PRICING_HASH);
        assertEq(bond, 1 ether);
    }

    function test_registerRouter_rejectsDuplicate() public {
        vm.prank(OWNER);
        registry.registerRouter{value: 1 ether}(ROUTER_ID, CATALOG_HASH, PRICING_HASH);
        vm.prank(OWNER);
        vm.expectRevert(RouterRegistry.RouterAlreadyRegistered.selector);
        registry.registerRouter{value: 1 ether}(ROUTER_ID, CATALOG_HASH, PRICING_HASH);
    }

    function test_registerRouter_revertsOnZeroBond() public {
        vm.prank(OWNER);
        vm.expectRevert(RouterRegistry.NoBond.selector);
        registry.registerRouter{value: 0}(ROUTER_ID, CATALOG_HASH, PRICING_HASH);
    }

    function test_addBond_increasesBond() public {
        vm.prank(OWNER);
        registry.registerRouter{value: 1 ether}(ROUTER_ID, CATALOG_HASH, PRICING_HASH);
        vm.prank(OWNER);
        registry.addBond{value: 0.5 ether}(ROUTER_ID);
        (,,,, uint256 bond) = registry.routers(ROUTER_ID);
        assertEq(bond, 1.5 ether);
    }

    function test_addBond_onlyRouterOwner() public {
        vm.prank(OWNER);
        registry.registerRouter{value: 1 ether}(ROUTER_ID, CATALOG_HASH, PRICING_HASH);
        vm.deal(ATTACKER, 1 ether);
        vm.prank(ATTACKER);
        vm.expectRevert(RouterRegistry.NotRouterOwner.selector);
        registry.addBond{value: 0.5 ether}(ROUTER_ID);
    }

    function test_updateCatalog_onlyRouterOwner() public {
        vm.prank(OWNER);
        registry.registerRouter{value: 1 ether}(ROUTER_ID, CATALOG_HASH, PRICING_HASH);
        vm.prank(ATTACKER);
        vm.expectRevert(RouterRegistry.NotRouterOwner.selector);
        registry.updateCatalog(ROUTER_ID, keccak256("new-catalog"));
    }

    function test_updateCatalog_writesNewHash() public {
        vm.prank(OWNER);
        registry.registerRouter{value: 1 ether}(ROUTER_ID, CATALOG_HASH, PRICING_HASH);
        bytes32 newHash = keccak256("router-1/catalog/v2");
        vm.prank(OWNER);
        registry.updateCatalog(ROUTER_ID, newHash);
        (,, bytes32 catalogHash,,) = registry.routers(ROUTER_ID);
        assertEq(catalogHash, newHash);
    }

    function test_updatePricing_writesNewHash() public {
        vm.prank(OWNER);
        registry.registerRouter{value: 1 ether}(ROUTER_ID, CATALOG_HASH, PRICING_HASH);
        bytes32 newHash = keccak256("router-1/pricing/v2");
        vm.prank(OWNER);
        registry.updatePricing(ROUTER_ID, newHash);
        (,,, bytes32 pricingHash,) = registry.routers(ROUTER_ID);
        assertEq(pricingHash, newHash);
    }

    function test_deactivateRouter_clearsActiveFlag() public {
        vm.prank(OWNER);
        registry.registerRouter{value: 1 ether}(ROUTER_ID, CATALOG_HASH, PRICING_HASH);
        vm.prank(OWNER);
        registry.deactivateRouter(ROUTER_ID);
        (, bool active,,,) = registry.routers(ROUTER_ID);
        assertFalse(active);
    }

    function test_withdrawBond_refundsAfterDeactivate() public {
        vm.prank(OWNER);
        registry.registerRouter{value: 1 ether}(ROUTER_ID, CATALOG_HASH, PRICING_HASH);
        vm.prank(OWNER);
        registry.deactivateRouter(ROUTER_ID);
        uint256 balanceBefore = OWNER.balance;
        vm.prank(OWNER);
        registry.withdrawBond(ROUTER_ID);
        (,,,, uint256 bond) = registry.routers(ROUTER_ID);
        assertEq(bond, 0);
        assertEq(OWNER.balance, balanceBefore + 1 ether);
    }

    function test_withdrawBond_revertsWhileActive() public {
        vm.prank(OWNER);
        registry.registerRouter{value: 1 ether}(ROUTER_ID, CATALOG_HASH, PRICING_HASH);
        vm.prank(OWNER);
        vm.expectRevert(RouterRegistry.RouterStillActive.selector);
        registry.withdrawBond(ROUTER_ID);
    }
}
