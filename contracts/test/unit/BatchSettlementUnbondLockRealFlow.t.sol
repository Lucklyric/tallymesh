// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";

contract BatchSettlementUnbondLockRealFlowTest is Test {
    BatchSettlement settlement;
    address constant OWNER = address(0xDEEDA);
    address constant SUBMITTER = address(0x5BB1);
    bytes32 constant BATCH_ID = bytes32("batch-real");
    bytes32 constant RECEIPTS_ROOT = keccak256("receipts");
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

    /// @dev Real-flow demonstration of the unbond lock. After a submitter
    /// posts a batch, `pendingBatchesOf == 1` and `unbond` is rejected. After
    /// the challenge window expires and `finalizeBatch` runs, the counter
    /// drops to zero and unbond is allowed again.
    function test_unbond_lockedAfterRealSubmit_clearedAfterFinalize() public {
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, RECEIPTS_ROOT, bytes32(0), 1);
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 1);

        vm.prank(SUBMITTER);
        vm.expectRevert(BatchSettlement.PendingBatchesPreventUnbond.selector);
        settlement.unbond(0.5 ether);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(BATCH_ID);
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 0);

        vm.prank(SUBMITTER);
        settlement.unbond(0.5 ether);
        assertEq(settlement.bondOf(SUBMITTER), 1.5 ether);
    }

    /// @dev Multiple pending batches block unbond until ALL are resolved.
    function test_unbond_remainsLockedWhileAnyBatchPending() public {
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(bytes32("batch-A"), RECEIPTS_ROOT, bytes32(0), 1);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(bytes32("batch-B"), RECEIPTS_ROOT, bytes32(0), 1);
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 2);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(bytes32("batch-A"));
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 1);

        vm.prank(SUBMITTER);
        vm.expectRevert(BatchSettlement.PendingBatchesPreventUnbond.selector);
        settlement.unbond(0.5 ether);

        settlement.finalizeBatch(bytes32("batch-B"));
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 0);
        vm.prank(SUBMITTER);
        settlement.unbond(0.5 ether);
    }
}
