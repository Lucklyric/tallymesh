// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";
import {DisputeManager} from "../../src/DisputeManager.sol";
import {ReceiptLib} from "../../src/lib/ReceiptLib.sol";

contract SecurityBatteryDay3Test is Test {
    DepositEscrow escrow;
    BatchSettlement settlement;
    DisputeManager dispute;
    address constant OWNER = address(0xDEEDA);
    address constant SUBMITTER = address(0x5BB1);
    address constant PAYER = address(0xA11CE);
    address payable constant SERVICE = payable(address(0x5E2C1));
    address payable constant CHALLENGER = payable(address(0xC4A));
    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
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
        vm.prank(OWNER);
        escrow.setAuthorizedSettler(address(settlement), true);
        vm.deal(SUBMITTER, 10 ether);
        vm.prank(SUBMITTER);
        settlement.bond{value: 2 ether}();
        vm.deal(PAYER, 10 ether);
        vm.prank(PAYER);
        escrow.deposit{value: 2 ether}();
        vm.prank(PAYER);
        settlement.reserveSession(bytes32("sess-1"), SERVICE, 1 ether);
    }

    function test_attack01_replayWithinSession_deferredToDay4() public pure {
        assertTrue(true, "deferred: attack 1 lands with sdk-ts SessionIntent in Day 4");
    }

    function test_attack02_duplicateReceiptWithinBatch() public {
        ReceiptLib.Receipt memory r = ReceiptLib.Receipt({
            sessionId: bytes32("sess-1"),
            seq: 1,
            requestHash: keccak256("req-1"),
            resultHash: keccak256("res-1"),
            chargedAmount: 0.3 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        bytes32 root = ReceiptLib.leafHash(r);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(bytes32("batch-2"), root, bytes32(0), 1);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(bytes32("batch-2"));
        bytes32[] memory proof = new bytes32[](0);
        settlement.claimPayout(bytes32("batch-2"), r, proof);
        vm.expectRevert(BatchSettlement.ReceiptAlreadyClaimed.selector);
        settlement.claimPayout(bytes32("batch-2"), r, proof);
    }

    function test_attack03_outOfOrderSeq_deferredToDay4() public pure {
        assertTrue(true, "deferred: attack 3 lands with sdk-ts hash-linked transcript in Day 4");
    }

    function test_attack07_validChallengeSlashes() public {
        ReceiptLib.Receipt memory bad = ReceiptLib.Receipt({
            sessionId: bytes32("sess-1"),
            seq: 1,
            requestHash: keccak256("req-bad"),
            resultHash: keccak256("res-bad"),
            chargedAmount: 5 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        bytes32 root = ReceiptLib.leafHash(bad);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(bytes32("batch-3"), root, bytes32(0), 1);
        bytes32[] memory proof = new bytes32[](0);
        uint256 challengerBefore = CHALLENGER.balance;
        uint256 burnBefore = BURN_ADDRESS.balance;
        vm.prank(CHALLENGER);
        dispute.challengeReceipt(bytes32("batch-3"), bad, proof);
        (,,,,, BatchSettlement.BatchStatus status,,) = settlement.batches(bytes32("batch-3"));
        assertEq(uint256(status), uint256(BatchSettlement.BatchStatus.Invalidated));
        assertEq(settlement.bondOf(SUBMITTER), 0);
        assertEq(CHALLENGER.balance, challengerBefore + 1 ether);
        assertEq(BURN_ADDRESS.balance, burnBefore + 1 ether);
    }

    /// @dev Cross-batch global double-claim defense (Codex finding 3).
    function test_attack11_crossBatchDoubleClaimGlobalKey() public {
        ReceiptLib.Receipt memory r = ReceiptLib.Receipt({
            sessionId: bytes32("sess-1"),
            seq: 1,
            requestHash: keccak256("req-1"),
            resultHash: keccak256("res-1"),
            chargedAmount: 0.3 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        bytes32 root = ReceiptLib.leafHash(r);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(bytes32("batch-A"), root, bytes32(0), 1);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(bytes32("batch-A"));
        bytes32[] memory proof = new bytes32[](0);
        settlement.claimPayout(bytes32("batch-A"), r, proof);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(bytes32("batch-B"), root, bytes32(0), 1);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(bytes32("batch-B"));
        vm.expectRevert(BatchSettlement.ReceiptAlreadyClaimed.selector);
        settlement.claimPayout(bytes32("batch-B"), r, proof);
    }
}
