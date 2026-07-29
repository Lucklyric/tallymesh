// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";
import {IBatchVerifier} from "../../src/interfaces/IBatchVerifier.sol";
import {ReceiptLib} from "../../src/lib/ReceiptLib.sol";

contract ClaimPayoutMockVerifier is IBatchVerifier {
    function verifyBatch(bytes32, uint256, uint256, bytes calldata) external pure returns (bool) {
        return true;
    }
}

contract ClaimPayoutSettlementModeTest is Test {
    DepositEscrow escrow;
    BatchSettlement settlement;
    ClaimPayoutMockVerifier verifier;

    address constant OWNER = address(0xDEEDA);
    address constant SUBMITTER = address(0x5BB1);
    address constant PAYER = address(0xA11CE);
    address payable constant SERVICE = payable(address(0x5E2C1));
    bytes32 constant BATCH_ID = bytes32("zk-claim-batch");
    bytes32 constant SESSION = bytes32("zk-claim-session");

    function setUp() public {
        vm.prank(OWNER);
        escrow = new DepositEscrow();
        vm.prank(OWNER);
        settlement = new BatchSettlement(address(escrow));
        verifier = new ClaimPayoutMockVerifier();

        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER, true);
        vm.prank(OWNER);
        settlement.setApprovedVerifier(address(verifier), true);
        vm.prank(OWNER);
        escrow.setAuthorizedSettler(address(settlement), true);
        vm.prank(OWNER);
        settlement.setLegacyReserveEnabled(true);

        vm.deal(SUBMITTER, 10 ether);
        vm.prank(SUBMITTER);
        settlement.bond{value: 1 ether}();

        vm.deal(PAYER, 10 ether);
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        vm.prank(PAYER);
        settlement.reserveSession(SESSION, SERVICE, 0.5 ether);
    }

    function test_claimPayout_succeedsForZkModeBatch() public {
        ReceiptLib.Receipt memory receipt = ReceiptLib.Receipt({
            sessionId: SESSION,
            seq: 1,
            requestHash: keccak256("req-1"),
            resultHash: keccak256("res-1"),
            chargedAmount: 0.3 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        bytes32 root = ReceiptLib.leafHash(receipt);

        vm.prank(SUBMITTER);
        settlement.submitZkBatch(BATCH_ID, root, bytes32(0), 1, address(verifier), hex"");

        bytes32[] memory proof = new bytes32[](0);
        uint256 serviceBalBefore = SERVICE.balance;
        uint256 gasBefore = gasleft();
        settlement.claimPayout(BATCH_ID, receipt, proof);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("claimPayout gas (ZK-mode, cold, N=1)", gasUsed);

        assertEq(SERVICE.balance - serviceBalBefore, 0.3 ether, "recipient must be paid");

        // shared claimedReceipt[] key — re-claim must revert
        vm.expectRevert(bytes4(keccak256("ReceiptAlreadyClaimed()")));
        settlement.claimPayout(BATCH_ID, receipt, proof);
    }

    /// Apples-to-apples optimistic baseline in the same fixture, so the
    /// ZK-mode delta is comparable.
    function test_claimPayout_optimisticBaseline_sameFixture() public {
        ReceiptLib.Receipt memory receipt = ReceiptLib.Receipt({
            sessionId: SESSION,
            seq: 1,
            requestHash: keccak256("req-1"),
            resultHash: keccak256("res-1"),
            chargedAmount: 0.3 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        bytes32 root = ReceiptLib.leafHash(receipt);

        bytes32 testBlobHash = bytes32(uint256(1));
        bytes32[] memory blobHashes = new bytes32[](1);
        blobHashes[0] = testBlobHash;
        vm.blobhashes(blobHashes);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(
            bytes32("opt-claim-batch"), root, bytes32(0), 1, testBlobHash
        );
        vm.warp(block.timestamp + 1);
        settlement.finalizeBatch(bytes32("opt-claim-batch"));

        bytes32[] memory proof = new bytes32[](0);
        uint256 gasBefore = gasleft();
        settlement.claimPayout(bytes32("opt-claim-batch"), receipt, proof);
        uint256 gasUsed = gasBefore - gasleft();
        emit log_named_uint("claimPayout gas (Optimistic, cold, N=1, same fixture)", gasUsed);
    }
}
