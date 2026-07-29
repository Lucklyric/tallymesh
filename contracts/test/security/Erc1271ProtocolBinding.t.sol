// code/contracts/test/security/Erc1271ProtocolBinding.t.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Signatures} from "../../src/lib/Signatures.sol";
import {ServiceRegistry} from "../../src/ServiceRegistry.sol";
import {PhantomERC1271} from "../unit/mocks/MockERC1271.sol";

/// @dev Attack 13 in §2.3. The PhantomERC1271 mock returns the ERC-1271
/// magic value for any (hash, signature) pair — proving that ERC-1271 alone
/// is insufficient. The protocol layer guards against this by requiring the
/// declared signer address to be present in `ServiceRegistry` for the relevant
/// service. This test asserts both pieces: the phantom validates anything
/// (so a naive verifier would accept it), AND the service registry rejects
/// the unbound address.
contract Erc1271ProtocolBindingTest is Test {
    ServiceRegistry registry;
    bytes32 constant SERVICE_ID = bytes32("svc-1");
    address owner = address(0xA11CE);

    function setUp() public {
        registry = new ServiceRegistry();
        vm.prank(owner);
        registry.registerService(SERVICE_ID, keccak256("meta"), keccak256("fee"));
    }

    function test_attack13_phantomValidatesAnything_butIsNotInRegistry() public {
        PhantomERC1271 phantom = new PhantomERC1271();
        bytes32 anyHash = keccak256("anything");
        bytes memory anySig = hex"00";
        assertTrue(
            Signatures.isValidContractSignature(address(phantom), anyHash, anySig),
            "ERC-1271 alone validates the phantom (the attack premise)"
        );
        assertFalse(
            registry.isServiceSigner(SERVICE_ID, address(phantom)),
            "ServiceRegistry rejects the unbound phantom address"
        );
    }

    function test_attack13_phantomEvenIfBoundOnceCanBeRevoked() public {
        PhantomERC1271 phantom = new PhantomERC1271();
        // Suppose the phantom were mistakenly added to the registry.
        vm.prank(owner);
        registry.setServiceSigner(SERVICE_ID, address(phantom), true);
        assertTrue(registry.isServiceSigner(SERVICE_ID, address(phantom)));
        // The owner-gated revoke restores safety.
        vm.prank(owner);
        registry.setServiceSigner(SERVICE_ID, address(phantom), false);
        assertFalse(registry.isServiceSigner(SERVICE_ID, address(phantom)));
    }
}
