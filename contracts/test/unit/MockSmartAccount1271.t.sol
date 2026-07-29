// code/contracts/test/unit/MockSmartAccount1271.t.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MockSmartAccount1271} from "./mocks/MockSmartAccount1271.sol";

contract MockSmartAccount1271Test is Test {
    uint256 ownerKey = 0xA0;
    address owner;
    MockSmartAccount1271 acct;

    function setUp() public {
        owner = vm.addr(ownerKey);
        acct = new MockSmartAccount1271(owner);
    }

    function test_validatesOwnerSignature() public view {
        bytes32 digest = keccak256("hello");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        assertEq(acct.isValidSignature(digest, sig), bytes4(0x1626ba7e));
    }

    function test_rejectsForeignSignature() public view {
        bytes32 digest = keccak256("hello");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBEEF, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        assertEq(acct.isValidSignature(digest, sig), bytes4(0xffffffff));
    }

    function test_rejectsTamperedHash() public view {
        bytes32 digest = keccak256("hello");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        bytes32 tampered = keccak256("goodbye");
        assertEq(acct.isValidSignature(tampered, sig), bytes4(0xffffffff));
    }
}
