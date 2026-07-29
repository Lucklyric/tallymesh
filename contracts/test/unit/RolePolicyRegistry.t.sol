// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RolePolicyRegistry} from "../../src/RolePolicyRegistry.sol";
import {ServiceRegistry} from "../../src/ServiceRegistry.sol";

contract RolePolicyRegistryTest is Test {
    ServiceRegistry serviceRegistry;
    RolePolicyRegistry policyRegistry;
    address constant OWNER = address(0xA11CE);
    bytes32 constant SERVICE_ID = bytes32("svc-1");
    bytes32 constant RESOURCE = bytes32("inference.text");
    bytes32 constant ROLE = bytes32("paying-customer");
    bytes32 constant ISSUER = bytes32("issuer-1");

    function setUp() public {
        serviceRegistry = new ServiceRegistry();
        policyRegistry = new RolePolicyRegistry(address(serviceRegistry));
        vm.prank(OWNER);
        serviceRegistry.registerService(SERVICE_ID, keccak256("meta"), keccak256("fee"));
    }

    function test_setRolePolicy_storesAndChecks() public {
        vm.prank(OWNER);
        policyRegistry.setRolePolicy(SERVICE_ID, RESOURCE, ROLE, 10_000, true);
        (uint256 maxPerCall, bool enabled) = policyRegistry.policy(SERVICE_ID, RESOURCE, ROLE);
        assertEq(maxPerCall, 10_000);
        assertTrue(enabled);
    }

    function test_setRolePolicy_onlyServiceOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(RolePolicyRegistry.NotServiceOwner.selector);
        policyRegistry.setRolePolicy(SERVICE_ID, RESOURCE, ROLE, 10_000, true);
    }

    function test_setRolePolicy_revertsForUnknownService() public {
        vm.prank(OWNER);
        vm.expectRevert(RolePolicyRegistry.NotServiceOwner.selector);
        policyRegistry.setRolePolicy(bytes32("unknown"), RESOURCE, ROLE, 10_000, true);
    }

    function test_setIssuerBinding_onlyServiceOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(RolePolicyRegistry.NotServiceOwner.selector);
        policyRegistry.setIssuerBinding(SERVICE_ID, ROLE, ISSUER, true);
    }

    function test_setIssuerBinding_addsAndChecks() public {
        vm.prank(OWNER);
        policyRegistry.setIssuerBinding(SERVICE_ID, ROLE, ISSUER, true);
        assertTrue(policyRegistry.isIssuerBound(SERVICE_ID, ROLE, ISSUER));
        assertFalse(policyRegistry.isIssuerBound(SERVICE_ID, ROLE, bytes32("issuer-2")));
    }

    function test_disablingPolicy_clearsEnabledFlag() public {
        vm.prank(OWNER);
        policyRegistry.setRolePolicy(SERVICE_ID, RESOURCE, ROLE, 10_000, true);
        vm.prank(OWNER);
        policyRegistry.setRolePolicy(SERVICE_ID, RESOURCE, ROLE, 10_000, false);
        (, bool enabled) = policyRegistry.policy(SERVICE_ID, RESOURCE, ROLE);
        assertFalse(enabled);
    }
}
