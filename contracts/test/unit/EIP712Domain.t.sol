// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {EIP712Domain} from "../../src/lib/EIP712Domain.sol";

contract EIP712DomainTest is Test {
    function test_typeHash_matchesCanonicalString() public pure {
        bytes32 expected =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        assertEq(EIP712Domain.TYPE_HASH, expected, "TYPE_HASH drift");
    }

    function test_domainSeparator_isStableForSameInputs() public view {
        bytes32 a = EIP712Domain.domainSeparator("TallyMesh", "1", 31337, address(0xBEEF));
        bytes32 b = EIP712Domain.domainSeparator("TallyMesh", "1", 31337, address(0xBEEF));
        assertEq(a, b, "domain separator must be deterministic");
    }

    function test_domainSeparator_changesWithChainId() public view {
        bytes32 a = EIP712Domain.domainSeparator("TallyMesh", "1", 31337, address(0xBEEF));
        bytes32 b = EIP712Domain.domainSeparator("TallyMesh", "1",     1, address(0xBEEF));
        assertTrue(a != b, "chainId must influence domain separator");
    }

    function test_domainSeparator_changesWithVerifyingContract() public view {
        bytes32 a = EIP712Domain.domainSeparator("TallyMesh", "1", 31337, address(0xBEEF));
        bytes32 b = EIP712Domain.domainSeparator("TallyMesh", "1", 31337, address(0xCAFE));
        assertTrue(a != b, "verifyingContract must influence domain separator");
    }

    function test_domainSeparator_changesWithName() public view {
        bytes32 a = EIP712Domain.domainSeparator("TallyMesh", "1", 31337, address(0xBEEF));
        bytes32 b = EIP712Domain.domainSeparator("TallyMash", "1", 31337, address(0xBEEF));
        assertTrue(a != b, "name must influence domain separator");
    }

    function test_domainSeparator_changesWithVersion() public view {
        bytes32 a = EIP712Domain.domainSeparator("TallyMesh", "1", 31337, address(0xBEEF));
        bytes32 b = EIP712Domain.domainSeparator("TallyMesh", "2", 31337, address(0xBEEF));
        assertTrue(a != b, "version must influence domain separator");
    }
}
