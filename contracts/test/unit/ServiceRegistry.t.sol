// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ServiceRegistry} from "../../src/ServiceRegistry.sol";

contract ServiceRegistryTest is Test {
    ServiceRegistry registry;
    address constant OWNER = address(0xA11CE);
    address constant SIGNER1 = address(0xB0B);
    address constant SIGNER2 = address(0xCA7);
    bytes32 constant SERVICE_ID = bytes32("svc-1");
    bytes32 constant METADATA_HASH = keccak256("https://svc-1.example/metadata.json");
    bytes32 constant FEE_HASH = keccak256("fee-schedule-v1");

    function setUp() public {
        registry = new ServiceRegistry();
    }

    function test_registerService_storesOwnerAndHashes() public {
        vm.prank(OWNER);
        registry.registerService(SERVICE_ID, METADATA_HASH, FEE_HASH);
        (address owner, bool active, bytes32 metaHash, bytes32 feeHash) = registry.services(SERVICE_ID);
        assertEq(owner, OWNER);
        assertTrue(active);
        assertEq(metaHash, METADATA_HASH);
        assertEq(feeHash, FEE_HASH);
    }

    function test_registerService_rejectsDuplicate() public {
        vm.prank(OWNER);
        registry.registerService(SERVICE_ID, METADATA_HASH, FEE_HASH);
        vm.prank(OWNER);
        vm.expectRevert(ServiceRegistry.ServiceAlreadyRegistered.selector);
        registry.registerService(SERVICE_ID, METADATA_HASH, FEE_HASH);
    }

    function test_setServiceSigner_onlyOwner() public {
        vm.prank(OWNER);
        registry.registerService(SERVICE_ID, METADATA_HASH, FEE_HASH);
        vm.prank(SIGNER2);
        vm.expectRevert(ServiceRegistry.NotServiceOwner.selector);
        registry.setServiceSigner(SERVICE_ID, SIGNER1, true);
    }

    function test_setServiceSigner_addsAndChecks() public {
        vm.prank(OWNER);
        registry.registerService(SERVICE_ID, METADATA_HASH, FEE_HASH);
        vm.prank(OWNER);
        registry.setServiceSigner(SERVICE_ID, SIGNER1, true);
        assertTrue(registry.isServiceSigner(SERVICE_ID, SIGNER1));
        assertFalse(registry.isServiceSigner(SERVICE_ID, SIGNER2));
    }

    function test_setServiceSigner_removes() public {
        vm.prank(OWNER);
        registry.registerService(SERVICE_ID, METADATA_HASH, FEE_HASH);
        vm.prank(OWNER);
        registry.setServiceSigner(SERVICE_ID, SIGNER1, true);
        assertTrue(registry.isServiceSigner(SERVICE_ID, SIGNER1));
        vm.prank(OWNER);
        registry.setServiceSigner(SERVICE_ID, SIGNER1, false);
        assertFalse(registry.isServiceSigner(SERVICE_ID, SIGNER1));
    }

    function test_deactivateService_clearsActiveFlag() public {
        vm.prank(OWNER);
        registry.registerService(SERVICE_ID, METADATA_HASH, FEE_HASH);
        vm.prank(OWNER);
        registry.deactivateService(SERVICE_ID);
        (, bool active,,) = registry.services(SERVICE_ID);
        assertFalse(active);
    }

    function test_deactivateService_onlyOwner() public {
        vm.prank(OWNER);
        registry.registerService(SERVICE_ID, METADATA_HASH, FEE_HASH);
        vm.prank(SIGNER1);
        vm.expectRevert(ServiceRegistry.NotServiceOwner.selector);
        registry.deactivateService(SERVICE_ID);
    }

    function test_isServiceSigner_returnsFalseForUnregistered() public view {
        assertFalse(registry.isServiceSigner(bytes32("nope"), SIGNER1));
    }

    function test_unauthorizedRegistryUpdate_blockedAtSetSigner() public {
        // Attack 17: unregistered party tries to set a signer.
        vm.prank(OWNER);
        registry.registerService(SERVICE_ID, METADATA_HASH, FEE_HASH);
        address attacker = address(0xBAD);
        vm.prank(attacker);
        vm.expectRevert(ServiceRegistry.NotServiceOwner.selector);
        registry.setServiceSigner(SERVICE_ID, SIGNER1, true);
    }
}
