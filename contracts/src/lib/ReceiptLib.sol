// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Receipt typing and Merkle helpers for batched settlement.
library ReceiptLib {
    bytes32 internal constant RECEIPT_TYPEHASH = keccak256(
        "Receipt(bytes32 sessionId,uint64 seq,bytes32 requestHash,bytes32 resultHash,uint256 chargedAmount,bytes32 statusCode,uint64 serviceTimestamp)"
    );

    struct Receipt {
        bytes32 sessionId;
        uint64 seq;
        bytes32 requestHash;
        bytes32 resultHash;
        uint256 chargedAmount;
        bytes32 statusCode;
        uint64 serviceTimestamp;
    }

    function leafHash(Receipt memory r) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                RECEIPT_TYPEHASH,
                r.sessionId,
                r.seq,
                r.requestHash,
                r.resultHash,
                r.chargedAmount,
                r.statusCode,
                r.serviceTimestamp
            )
        );
    }

    function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function verifyProof(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computed = leaf;
        uint256 len = proof.length;
        for (uint256 i = 0; i < len; ++i) {
            computed = hashPair(computed, proof[i]);
        }
        return computed == root;
    }
}
