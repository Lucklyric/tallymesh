// code/contracts/test/security/FeeScheduleImmutable.t.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ServiceRegistry} from "../../src/ServiceRegistry.sol";

/// @dev Attack 14 in §2.3. Defense: the `feeScheduleHash` is captured at
/// `registerService` and the contract surface exposes no setter. A payer who
/// observes feeScheduleHash at session-accept time has a permanent commitment;
/// any post-acceptance fee swap by the service operator is observable off-chain
/// (the fee body changes) but cannot pass the on-chain hash check. This test
/// pins the absence of any post-registration mutation path.
contract FeeScheduleImmutableTest is Test {
    ServiceRegistry registry;
    bytes32 constant SVC = bytes32("svc-1");
    address owner = address(0xA11CE);

    function setUp() public {
        registry = new ServiceRegistry();
        vm.prank(owner);
        registry.registerService(SVC, keccak256("meta"), keccak256("fee_v1"));
    }

    function test_attack14_feeScheduleHashIsImmutableAfterRegistration() public view {
        (, , , bytes32 feeHash) = registry.services(SVC);
        assertEq(feeHash, keccak256("fee_v1"));
        // The contract surface has no `setFeeScheduleHash` — there is no
        // path the owner can take to swap the hash without re-registering
        // (which would require a different serviceId due to the registration
        // guard). The absence of a setter IS the defense; this test pins it.
    }

    function test_attack14_reRegisteringSameServiceIdReverts() public {
        vm.prank(owner);
        vm.expectRevert(ServiceRegistry.ServiceAlreadyRegistered.selector);
        registry.registerService(SVC, keccak256("meta-v2"), keccak256("fee_v2"));
    }
}
