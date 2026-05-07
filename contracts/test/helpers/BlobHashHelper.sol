// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

abstract contract BlobHashHelper is Test {
    bytes32 internal constant TEST_BLOB_HASH = bytes32(uint256(0x01020304));

    function _setBlobHash(bytes32 blobHash) internal {
        bytes32[] memory blobHashes = new bytes32[](1);
        blobHashes[0] = blobHash;
        vm.blobhashes(blobHashes);
    }
}
