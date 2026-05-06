// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";

contract BatchSettlementSubmitTest is Test {
    BatchSettlement settlement;
    address constant OWNER = address(0xDEEDA);
    address constant SUBMITTER = address(0x5BB1);
    bytes32 constant BATCH_ID = bytes32("batch-1");
    bytes32 constant RECEIPTS_ROOT = keccak256("receipts");
    bytes32 constant DELTAS_ROOT = keccak256("deltas");
    uint256 constant CHALLENGE_WINDOW = 900;

    function setUp() public {
        vm.prank(OWNER);
        settlement = new BatchSettlement(address(0xE5C20E));
        vm.prank(OWNER);
        settlement.setChallengeWindow(uint64(CHALLENGE_WINDOW));
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER, true);
        vm.deal(SUBMITTER, 10 ether);
        vm.prank(SUBMITTER);
        settlement.bond{value: 2 ether}();
    }

    function test_submitBatch_storesHeader() public {
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, RECEIPTS_ROOT, DELTAS_ROOT, 100);
        (
            address submitter,
            uint256 receiptCount,
            uint64 submittedAt,
            uint64 challengeDeadline,
            uint256 bondAtSubmission,
            BatchSettlement.BatchStatus status,
            bytes32 receiptsRoot,
            bytes32 deltasRoot
        ) = settlement.batches(BATCH_ID);
        assertEq(submitter, SUBMITTER);
        assertEq(receiptCount, 100);
        assertEq(submittedAt, uint64(block.timestamp));
        assertEq(challengeDeadline, uint64(block.timestamp + CHALLENGE_WINDOW));
        assertEq(bondAtSubmission, 2 ether);
        assertEq(uint256(status), uint256(BatchSettlement.BatchStatus.Pending));
        assertEq(receiptsRoot, RECEIPTS_ROOT);
        assertEq(deltasRoot, DELTAS_ROOT);
    }

    function test_submitBatch_incrementsPendingBatches() public {
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, RECEIPTS_ROOT, DELTAS_ROOT, 100);
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 1);
    }

    function test_submitBatch_onlyAuthorizedSubmitter() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(BatchSettlement.NotAuthorizedSubmitter.selector);
        settlement.submitOptimisticBatch(BATCH_ID, RECEIPTS_ROOT, DELTAS_ROOT, 100);
    }

    function test_submitBatch_rejectsDuplicate() public {
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, RECEIPTS_ROOT, DELTAS_ROOT, 100);
        vm.prank(SUBMITTER);
        vm.expectRevert(BatchSettlement.BatchAlreadyExists.selector);
        settlement.submitOptimisticBatch(BATCH_ID, RECEIPTS_ROOT, DELTAS_ROOT, 100);
    }

    function test_submitBatch_emitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit BatchSettlement.BatchSubmitted(BATCH_ID, SUBMITTER, RECEIPTS_ROOT, DELTAS_ROOT, 100, uint64(block.timestamp + CHALLENGE_WINDOW));
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, RECEIPTS_ROOT, DELTAS_ROOT, 100);
    }

    function test_setChallengeWindow_onlyOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(BatchSettlement.NotOwner.selector);
        settlement.setChallengeWindow(60);
    }

    function test_submitBatch_revertsWithZeroBond() public {
        address submitter2 = address(0x5BB2);
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(submitter2, true);
        vm.prank(submitter2);
        vm.expectRevert(BatchSettlement.NoBond.selector);
        settlement.submitOptimisticBatch(bytes32("batch-2"), RECEIPTS_ROOT, DELTAS_ROOT, 100);
    }
}
