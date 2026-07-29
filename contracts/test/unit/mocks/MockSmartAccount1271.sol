// code/contracts/test/unit/mocks/MockSmartAccount1271.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @dev ERC-1271 smart-account mock that validates signatures against a single
/// owner EOA. Suitable for benchmarks that produce many distinct signed digests
/// against the same smart-account address.
contract MockSmartAccount1271 is IERC1271 {
    bytes4 public constant MAGIC = 0x1626ba7e;
    address public immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (ECDSA.recover(hash, signature) == owner) return MAGIC;
        return 0xffffffff;
    }
}
