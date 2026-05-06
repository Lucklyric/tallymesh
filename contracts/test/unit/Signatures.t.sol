// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Signatures} from "../../src/lib/Signatures.sol";
import {MockERC1271, PhantomERC1271} from "./mocks/MockERC1271.sol";

contract SignaturesTest is Test {
    uint256 constant ALICE_PK = 0xA11CE;

    function test_recoverEOA_recoversCorrectAddress() public {
        bytes32 digest = keccak256("hello");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        address recovered = Signatures.recoverEOA(digest, sig);
        assertEq(recovered, vm.addr(ALICE_PK));
    }

    /// @dev Regression for ECDSA signature malleability — attack 12 in §2.3.
    /// OZ ECDSA reverts with `ECDSAInvalidSignatureS` for any `s` above the half-order.
    /// The library call is wrapped in `_recoverEOA` because `vm.expectRevert` only
    /// catches reverts at external-call boundaries; library internal calls are inlined.
    function test_recoverEOA_revertsOnHighS() public {
        bytes32 digest = keccak256("hello");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 highS = bytes32(n - uint256(s));
        uint8 flippedV = v == 27 ? 28 : 27;
        bytes memory sig = abi.encodePacked(r, highS, flippedV);
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, highS));
        this._recoverEOA(digest, sig);
    }

    function test_recoverEOA_revertsOnInvalidLength() public {
        bytes memory sig = hex"0011";
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, sig.length));
        this._recoverEOA(keccak256("x"), sig);
    }

    function test_isValidContractSignature_returnsTrueForValidWallet() public {
        bytes32 digest = keccak256("hello");
        bytes memory sig = hex"deadbeef";
        MockERC1271 wallet = new MockERC1271(digest, sig);
        assertTrue(Signatures.isValidContractSignature(address(wallet), digest, sig));
    }

    function test_isValidContractSignature_returnsFalseForWrongHash() public {
        bytes32 digest = keccak256("hello");
        bytes memory sig = hex"deadbeef";
        MockERC1271 wallet = new MockERC1271(digest, sig);
        assertFalse(Signatures.isValidContractSignature(address(wallet), keccak256("nope"), sig));
    }

    /// @dev Demonstrates that ERC-1271 alone is insufficient — a phantom wallet validates anything.
    /// The protocol layer must additionally bind the contract to a registry. See attack 13 in §2.3.
    function test_phantomWallet_acceptsAnyHash() public {
        PhantomERC1271 phantom = new PhantomERC1271();
        assertTrue(Signatures.isValidContractSignature(address(phantom), keccak256("a"), hex"00"));
        assertTrue(Signatures.isValidContractSignature(address(phantom), keccak256("b"), hex"ff"));
    }

    function _recoverEOA(bytes32 digest, bytes memory signature) external pure {
        Signatures.recoverEOA(digest, signature);
    }
}
