// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ReceiptLib} from "../../src/lib/ReceiptLib.sol";

contract ReceiptLibTest is Test {
    function test_typeHash_matchesCanonicalString() public pure {
        bytes32 expected = keccak256(
            "Receipt(bytes32 sessionId,uint64 seq,bytes32 requestHash,bytes32 resultHash,uint256 chargedAmount,bytes32 statusCode,uint64 serviceTimestamp)"
        );
        assertEq(ReceiptLib.RECEIPT_TYPEHASH, expected, "RECEIPT_TYPEHASH drift");
    }

    function test_leafHash_isDomainSeparated() public pure {
        ReceiptLib.Receipt memory r = ReceiptLib.Receipt({
            sessionId: bytes32(uint256(1)),
            seq: 1,
            requestHash: bytes32(uint256(2)),
            resultHash: bytes32(uint256(3)),
            chargedAmount: 100,
            statusCode: bytes32("OK"),
            serviceTimestamp: 1700000000
        });
        bytes32 leaf = ReceiptLib.leafHash(r);
        // Recompute manually with the typehash and confirm equality.
        bytes32 expected = keccak256(
            abi.encode(
                ReceiptLib.RECEIPT_TYPEHASH,
                r.sessionId,
                r.seq,
                r.requestHash,
                r.resultHash,
                r.chargedAmount,
                r.statusCode,
                r.serviceTimestamp
            )
        );
        assertEq(leaf, expected);
    }

    function test_leafHash_differsFromRawAbiEncode() public pure {
        ReceiptLib.Receipt memory r = ReceiptLib.Receipt({
            sessionId: bytes32(uint256(1)),
            seq: 1,
            requestHash: bytes32(uint256(2)),
            resultHash: bytes32(uint256(3)),
            chargedAmount: 100,
            statusCode: bytes32("OK"),
            serviceTimestamp: 1700000000
        });
        bytes32 leaf = ReceiptLib.leafHash(r);
        bytes32 rawHash = keccak256(
            abi.encode(
                r.sessionId, r.seq, r.requestHash, r.resultHash, r.chargedAmount, r.statusCode, r.serviceTimestamp
            )
        );
        assertTrue(leaf != rawHash, "leaf must include typehash to defeat collision");
    }

    function test_verifyProof_acceptsValidLeaf() public pure {
        bytes32 a = keccak256("a");
        bytes32 b = keccak256("b");
        bytes32 root = ReceiptLib.hashPair(a, b);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = b;
        assertTrue(ReceiptLib.verifyProof(proof, root, a));
    }

    function test_verifyProof_rejectsTamperedLeaf() public pure {
        bytes32 a = keccak256("a");
        bytes32 b = keccak256("b");
        bytes32 root = ReceiptLib.hashPair(a, b);
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = b;
        assertFalse(ReceiptLib.verifyProof(proof, root, keccak256("tampered")));
    }

    function test_hashPair_isCommutative() public pure {
        bytes32 a = keccak256("a");
        bytes32 b = keccak256("b");
        assertEq(ReceiptLib.hashPair(a, b), ReceiptLib.hashPair(b, a));
    }
}
