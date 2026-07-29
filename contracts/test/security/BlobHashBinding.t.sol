// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";

contract BlobHashBindingTest is Test {
    BatchSettlement settlement;

    address constant OWNER = address(0xDEEDA);
    address constant SUBMITTER = address(0x5BB1);
    bytes32 constant BATCH_ID = bytes32("batch-1");
    bytes32 constant RECEIPTS_ROOT = keccak256("receipts");
    bytes32 constant DELTAS_ROOT = keccak256("deltas");
    bytes32 constant BLOB_HASH = bytes32(uint256(0x01020304));

    function setUp() public {
        vm.prank(OWNER);
        settlement = new BatchSettlement(address(0xE5C20E));
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER, true);
        vm.deal(SUBMITTER, 10 ether);
        vm.prank(SUBMITTER);
        settlement.bond{value: 2 ether}();
    }

    function test_submitOptimisticBatch_revertsWhenBlobNotPresent() public {
        vm.prank(SUBMITTER);
        vm.expectRevert(BatchSettlement.BlobNotPresent.selector);
        settlement.submitOptimisticBatch(BATCH_ID, RECEIPTS_ROOT, DELTAS_ROOT, 100, BLOB_HASH);
    }

    function test_submitOptimisticBatch_revertsWhenBlobHashMismatch() public {
        _setBlobHash(BLOB_HASH);

        vm.prank(SUBMITTER);
        vm.expectRevert(BatchSettlement.BlobHashMismatch.selector);
        settlement.submitOptimisticBatch(BATCH_ID, RECEIPTS_ROOT, DELTAS_ROOT, 100, bytes32(uint256(0x01020305)));
    }

    function test_submitOptimisticBatch_succeedsWhenBlobHashMatches() public {
        _setBlobHash(BLOB_HASH);

        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, RECEIPTS_ROOT, DELTAS_ROOT, 100, BLOB_HASH);

        (address submitter,,,,,,, bytes32 deltasRoot) = settlement.batches(BATCH_ID);
        assertEq(submitter, SUBMITTER);
        assertEq(deltasRoot, DELTAS_ROOT);
    }

    function _setBlobHash(bytes32 blobHash) internal {
        bytes32[] memory blobHashes = new bytes32[](1);
        blobHashes[0] = blobHash;
        vm.blobhashes(blobHashes);
    }
}
