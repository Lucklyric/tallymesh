// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BlobHashHelper} from "../helpers/BlobHashHelper.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";
import {DisputeManager} from "../../src/DisputeManager.sol";
import {ReceiptLib} from "../../src/lib/ReceiptLib.sol";

contract DisputeManagerTest is BlobHashHelper {
    DepositEscrow escrow;
    BatchSettlement settlement;
    DisputeManager dispute;
    address constant OWNER = address(0xDEEDA);
    address constant SUBMITTER = address(0x5BB1);
    address payable constant CHALLENGER = payable(address(0xC4A));
    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    bytes32 constant BATCH_ID = bytes32("batch-1");
    bytes32 constant SESSION = bytes32("sess-1");
    uint256 constant CHALLENGE_WINDOW = 900;
    uint256 constant CHARGED_CEILING = 1 ether;

    function setUp() public {
        vm.prank(OWNER);
        escrow = new DepositEscrow();
        vm.prank(OWNER);
        settlement = new BatchSettlement(address(escrow));
        vm.prank(OWNER);
        dispute = new DisputeManager(address(settlement));
        vm.prank(OWNER);
        settlement.setChallengeWindow(uint64(CHALLENGE_WINDOW));
        vm.prank(OWNER);
        settlement.setChargedCeiling(CHARGED_CEILING);
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER, true);
        vm.prank(OWNER);
        settlement.setDisputeManager(address(dispute));
        vm.deal(SUBMITTER, 10 ether);
        vm.prank(SUBMITTER);
        settlement.bond{value: 2 ether}();
    }

    function _badReceiptRoot() internal view returns (bytes32 root, ReceiptLib.Receipt memory r) {
        r = ReceiptLib.Receipt({
            sessionId: SESSION,
            seq: 1,
            requestHash: keccak256("req"),
            resultHash: keccak256("res"),
            chargedAmount: 5 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        root = ReceiptLib.leafHash(r);
    }

    function test_challenge_emitsEventWithTimestamp() public {
        (bytes32 root, ReceiptLib.Receipt memory r) = _badReceiptRoot();
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        bytes32[] memory proof = new bytes32[](0);
        vm.warp(block.timestamp + 60);
        uint64 expectedAt = uint64(block.timestamp);
        vm.expectEmit(true, true, false, true);
        emit DisputeManager.BatchChallenged(BATCH_ID, CHALLENGER, expectedAt);
        vm.prank(CHALLENGER);
        dispute.challengeReceipt(BATCH_ID, r, proof);
    }

    function test_challenge_invalidatesBatchAndSlashesBondAndDecrementsPending() public {
        (bytes32 root, ReceiptLib.Receipt memory r) = _badReceiptRoot();
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 1);
        uint256 challengerBefore = CHALLENGER.balance;
        uint256 burnBefore = BURN_ADDRESS.balance;
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(CHALLENGER);
        dispute.challengeReceipt(BATCH_ID, r, proof);
        (,,,,, BatchSettlement.BatchStatus status,,) = settlement.batches(BATCH_ID);
        assertEq(uint256(status), uint256(BatchSettlement.BatchStatus.Invalidated));
        assertEq(settlement.bondOf(SUBMITTER), 0);
        assertEq(CHALLENGER.balance, challengerBefore + 1 ether);
        assertEq(BURN_ADDRESS.balance, burnBefore + 1 ether);
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 0);
    }

    function test_challenge_revertsAfterDeadline() public {
        (bytes32 root, ReceiptLib.Receipt memory r) = _badReceiptRoot();
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        bytes32[] memory proof = new bytes32[](0);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        vm.prank(CHALLENGER);
        vm.expectRevert(DisputeManager.ChallengeWindowClosed.selector);
        dispute.challengeReceipt(BATCH_ID, r, proof);
    }

    function test_challenge_revertsOnInvalidProof() public {
        (bytes32 root,) = _badReceiptRoot();
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        bytes32[] memory proof = new bytes32[](0);
        ReceiptLib.Receipt memory wrongLeaf = ReceiptLib.Receipt({
            sessionId: SESSION,
            seq: 999,
            requestHash: keccak256("other"),
            resultHash: keccak256("other"),
            chargedAmount: 5 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        vm.prank(CHALLENGER);
        vm.expectRevert(DisputeManager.InvalidReceiptProof.selector);
        dispute.challengeReceipt(BATCH_ID, wrongLeaf, proof);
    }

    function test_challenge_revertsOnLawfulReceipt() public {
        ReceiptLib.Receipt memory good = ReceiptLib.Receipt({
            sessionId: SESSION,
            seq: 1,
            requestHash: keccak256("req"),
            resultHash: keccak256("res"),
            chargedAmount: 0.5 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        bytes32 root = ReceiptLib.leafHash(good);
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(CHALLENGER);
        vm.expectRevert(DisputeManager.ChallengeFailedNoFraud.selector);
        dispute.challengeReceipt(BATCH_ID, good, proof);
    }

    function test_challenge_usesCurrentSettlementChargedCeiling() public {
        vm.prank(OWNER);
        settlement.setChargedCeiling(0.25 ether);
        ReceiptLib.Receipt memory receipt = ReceiptLib.Receipt({
            sessionId: SESSION,
            seq: 1,
            requestHash: keccak256("req"),
            resultHash: keccak256("res"),
            chargedAmount: 0.5 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        bytes32 root = ReceiptLib.leafHash(receipt);
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(CHALLENGER);
        dispute.challengeReceipt(BATCH_ID, receipt, proof);
        (,,,,, BatchSettlement.BatchStatus status,,) = settlement.batches(BATCH_ID);
        assertEq(uint256(status), uint256(BatchSettlement.BatchStatus.Invalidated));
    }

    function test_challenge_revertsForFinalizedBatch() public {
        (bytes32 root, ReceiptLib.Receipt memory r) = _badReceiptRoot();
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(BATCH_ID);
        bytes32[] memory proof = new bytes32[](0);
        vm.prank(CHALLENGER);
        vm.expectRevert(DisputeManager.ChallengeWindowClosed.selector);
        dispute.challengeReceipt(BATCH_ID, r, proof);
    }
}
