// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BlobHashHelper} from "../helpers/BlobHashHelper.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";
import {ReceiptLib} from "../../src/lib/ReceiptLib.sol";

contract BatchSettlementFinalizeTest is BlobHashHelper {
    BatchSettlement settlement;
    DepositEscrow escrow;
    address constant OWNER = address(0xDEEDA);
    address constant SUBMITTER = address(0x5BB1);
    address constant PAYER = address(0xA11CE);
    address payable constant SERVICE = payable(address(0x5E2C1));
    bytes32 constant BATCH_ID = bytes32("batch-1");
    bytes32 constant SESSION = bytes32("sess-1");
    uint256 constant CHALLENGE_WINDOW = 900;

    function setUp() public {
        vm.prank(OWNER);
        escrow = new DepositEscrow();
        vm.prank(OWNER);
        settlement = new BatchSettlement(address(escrow));
        vm.prank(OWNER);
        settlement.setChallengeWindow(uint64(CHALLENGE_WINDOW));
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER, true);
        vm.prank(OWNER);
        escrow.setAuthorizedSettler(address(settlement), true);
        vm.prank(OWNER);
        settlement.setLegacyReserveEnabled(true);
        vm.deal(SUBMITTER, 10 ether);
        vm.prank(SUBMITTER);
        settlement.bond{value: 2 ether}();
        vm.deal(PAYER, 10 ether);
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        vm.prank(PAYER);
        settlement.reserveSession(SESSION, SERVICE, 0.5 ether);
    }

    function _singleReceiptRoot() internal view returns (bytes32 root, ReceiptLib.Receipt memory r) {
        r = ReceiptLib.Receipt({
            sessionId: SESSION,
            seq: 1,
            requestHash: keccak256("req-1"),
            resultHash: keccak256("res-1"),
            chargedAmount: 0.3 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        root = ReceiptLib.leafHash(r);
    }

    function test_finalize_marksFinalizedAndDecrementsPending() public {
        (bytes32 root,) = _singleReceiptRoot();
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 1);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(BATCH_ID);
        (,,,,, BatchSettlement.BatchStatus status,,) = settlement.batches(BATCH_ID);
        assertEq(uint256(status), uint256(BatchSettlement.BatchStatus.Finalized));
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 0);
    }

    function test_finalize_revertsBeforeWindow() public {
        (bytes32 root,) = _singleReceiptRoot();
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        vm.expectRevert(BatchSettlement.ChallengeWindowOpen.selector);
        settlement.finalizeBatch(BATCH_ID);
    }

    function test_finalize_revertsForUnknownBatch() public {
        vm.expectRevert(BatchSettlement.BatchNotFound.selector);
        settlement.finalizeBatch(bytes32("none"));
    }

    function test_claimPayout_paysSessionRecipient() public {
        (bytes32 root, ReceiptLib.Receipt memory r) = _singleReceiptRoot();
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(BATCH_ID);
        bytes32[] memory proof = new bytes32[](0);
        settlement.claimPayout(BATCH_ID, r, proof);
        assertEq(SERVICE.balance, 0.3 ether);
    }

    function test_claimPayout_revertsWhenNotFinalized() public {
        (bytes32 root, ReceiptLib.Receipt memory r) = _singleReceiptRoot();
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(BatchSettlement.BatchNotFinalized.selector);
        settlement.claimPayout(BATCH_ID, r, proof);
    }

    function test_claimPayout_revertsForUnknownSession() public {
        ReceiptLib.Receipt memory orphan = ReceiptLib.Receipt({
            sessionId: bytes32("never-opened"),
            seq: 1,
            requestHash: keccak256("req"),
            resultHash: keccak256("res"),
            chargedAmount: 0.1 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        bytes32 root = ReceiptLib.leafHash(orphan);
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(BATCH_ID);
        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(BatchSettlement.SessionNotFound.selector);
        settlement.claimPayout(BATCH_ID, orphan, proof);
    }

    function test_claimPayout_revertsOnInvalidProof() public {
        (bytes32 root,) = _singleReceiptRoot();
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(BATCH_ID);
        ReceiptLib.Receipt memory tampered = ReceiptLib.Receipt({
            sessionId: SESSION,
            seq: 99,
            requestHash: keccak256("req-1"),
            resultHash: keccak256("res-1"),
            chargedAmount: 0.3 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(BatchSettlement.InvalidReceiptProof.selector);
        settlement.claimPayout(BATCH_ID, tampered, proof);
    }

    function test_claimPayout_rejectsSameReceiptInSameBatch() public {
        (bytes32 root, ReceiptLib.Receipt memory r) = _singleReceiptRoot();
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(BATCH_ID);
        bytes32[] memory proof = new bytes32[](0);
        settlement.claimPayout(BATCH_ID, r, proof);
        vm.expectRevert(BatchSettlement.ReceiptAlreadyClaimed.selector);
        settlement.claimPayout(BATCH_ID, r, proof);
    }

    /// @dev Cross-batch global double-claim defense (Codex finding 3).
    function test_claimPayout_rejectsCrossBatchDoubleClaim() public {
        (bytes32 root, ReceiptLib.Receipt memory r) = _singleReceiptRoot();
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1, TEST_BLOB_HASH);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(BATCH_ID);
        bytes32[] memory proof = new bytes32[](0);
        settlement.claimPayout(BATCH_ID, r, proof);
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(bytes32("batch-2"), root, bytes32(0), 1, TEST_BLOB_HASH);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(bytes32("batch-2"));
        vm.expectRevert(BatchSettlement.ReceiptAlreadyClaimed.selector);
        settlement.claimPayout(bytes32("batch-2"), r, proof);
    }
}
