// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @dev Test double: returns valid magic only when both the hash and signature match
/// the values configured at construction.
contract MockERC1271 is IERC1271 {
    bytes32 public expectedHash;
    bytes public expectedSignature;
    bytes4 public constant MAGIC = 0x1626ba7e;

    constructor(bytes32 hash_, bytes memory signature_) {
        expectedHash = hash_;
        expectedSignature = signature_;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (hash == expectedHash && keccak256(signature) == keccak256(expectedSignature)) {
            return MAGIC;
        }
        return 0xffffffff;
    }
}

/// @dev Test double for the phantom-signer attack (§2.3 attack 13): returns MAGIC for any input.
contract PhantomERC1271 is IERC1271 {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return 0x1626ba7e;
    }
}
