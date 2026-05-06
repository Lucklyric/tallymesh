// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";
import {CircomBatchVerifier} from "../../src/zk/CircomBatchVerifier.sol";
import {BatchValidityGroth16Verifier} from "../../src/zk/BatchValidityGroth16Verifier.sol";
import {IBatchVerifier} from "../../src/interfaces/IBatchVerifier.sol";
import {ReceiptLib} from "../../src/lib/ReceiptLib.sol";

/// @dev Minimal mock verifier used to drive failure paths without a real proof.
contract _MockVerifier is IBatchVerifier {
    bool public answer;
    constructor(bool initial) { answer = initial; }
    function setAnswer(bool a) external { answer = a; }
    function verifyBatch(bytes32, uint256, uint256, bytes calldata) external view returns (bool) {
        return answer;
    }
}

contract BatchSettlementZkTest is Test {
    DepositEscrow escrow;
    BatchSettlement settlement;
    CircomBatchVerifier circomAdapter;
    BatchValidityGroth16Verifier groth16;
    _MockVerifier mock;

    address constant OWNER = address(0xDEEDA);
    address constant SUBMITTER = address(0x5BB1);
    address constant PAYER = address(0xCAFE);
    address payable constant SERVICE = payable(address(0x5E2C1));
    bytes32 constant SESSION = bytes32("zk-sess-1");
    bytes32 constant BATCH_ID = bytes32("zk-batch-1");

    // Fixture from zk/fixtures/proof.json + public.json (same values as CircomBatchVerifier.t.sol).
    bytes32 constant RECEIPTS_ROOT = 0x10d07585399cb65d06d496c32e2246c636f436510b0637ecaf155f0ddce9f8e3;
    uint256 constant RECEIPT_COUNT = 4;
    uint256 constant CHARGED_CEILING = 1_000_000_000;

    function _proofFixture() internal pure returns (bytes memory) {
        uint256[2] memory a = [
            uint256(12072786314324392949018055869985872548767102581751090816847375124952104563963),
            uint256(3073572559425341698816097753196977236977346854669974266204279780797735217849)
        ];
        uint256[2][2] memory b = [
            [uint256(21272041174551566821619849055567492274146664711343729733000831864351999110196), uint256(17063925035055354372021214682730662321888801262824471543641701803478190905230)],
            [uint256(21591639894601882780017209373616668196134517309901964898518430303059262436917), uint256(15503579737221610311205097919148761397080447087256912351236776433351967361680)]
        ];
        uint256[2] memory c = [
            uint256(12855804017717458005698454909728435589190983861447700776084435310708892950565),
            uint256(10153692300512818981466626845906469145398809320214628070824571802064466196142)
        ];
        return abi.encode(a, b, c);
    }

    function setUp() public {
        vm.prank(OWNER);
        escrow = new DepositEscrow();
        vm.prank(OWNER);
        settlement = new BatchSettlement(address(escrow));
        groth16 = new BatchValidityGroth16Verifier();
        circomAdapter = new CircomBatchVerifier(address(groth16));
        mock = new _MockVerifier(true);

        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER, true);
        vm.prank(OWNER);
        escrow.setAuthorizedSettler(address(settlement), true);
        vm.prank(OWNER);
        settlement.setApprovedVerifier(address(circomAdapter), true);
        vm.prank(OWNER);
        settlement.setApprovedVerifier(address(mock), true);
        vm.prank(OWNER);
        settlement.setChargedCeiling(CHARGED_CEILING);

        vm.deal(SUBMITTER, 10 ether);
        vm.prank(SUBMITTER);
        settlement.bond{value: 2 ether}();
        vm.deal(PAYER, 10 ether);
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        vm.prank(PAYER);
        settlement.reserveSession(SESSION, SERVICE, 0.5 ether);
    }

    function test_submitZkBatch_requiresApprovedVerifier() public {
        _MockVerifier unapproved = new _MockVerifier(true);
        vm.prank(SUBMITTER);
        vm.expectRevert(BatchSettlement.VerifierNotApproved.selector);
        settlement.submitZkBatch(BATCH_ID, RECEIPTS_ROOT, bytes32(0), RECEIPT_COUNT, address(unapproved), hex"");
    }

    function test_submitZkBatch_rejectsInvalidProof() public {
        // Mock returns false -> VerifierRejected
        mock.setAnswer(false);
        vm.prank(SUBMITTER);
        vm.expectRevert(BatchSettlement.InvalidValidityProof.selector);
        settlement.submitZkBatch(BATCH_ID, RECEIPTS_ROOT, bytes32(0), RECEIPT_COUNT, address(mock), hex"");
    }

    function test_submitZkBatch_finalizesImmediately() public {
        bytes memory proof = _proofFixture();
        vm.prank(SUBMITTER);
        settlement.submitZkBatch(BATCH_ID, RECEIPTS_ROOT, bytes32(0), RECEIPT_COUNT, address(circomAdapter), proof);
        (,,,,, BatchSettlement.BatchStatus status,,) = settlement.batches(BATCH_ID);
        assertEq(uint256(status), uint256(BatchSettlement.BatchStatus.Finalized));
        assertEq(uint256(settlement.settlementModeOf(BATCH_ID)), uint256(BatchSettlement.SettlementMode.ZK));
        assertEq(settlement.verifierOf(BATCH_ID), address(circomAdapter));
    }

    function test_submitZkBatch_doesNotIncrementPendingBatches() public {
        bytes memory proof = _proofFixture();
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 0);
        vm.prank(SUBMITTER);
        settlement.submitZkBatch(BATCH_ID, RECEIPTS_ROOT, bytes32(0), RECEIPT_COUNT, address(circomAdapter), proof);
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 0);
    }

    function test_submitZkBatch_emitsZkBatchSubmittedAndFinalized() public {
        bytes memory proof = _proofFixture();
        vm.expectEmit(true, true, true, true);
        emit BatchSettlement.ZkBatchSubmitted(BATCH_ID, SUBMITTER, address(circomAdapter), RECEIPTS_ROOT, RECEIPT_COUNT);
        vm.expectEmit(true, true, false, true);
        emit BatchSettlement.BatchSubmitted(BATCH_ID, SUBMITTER, RECEIPTS_ROOT, bytes32(0), RECEIPT_COUNT, uint64(block.timestamp));
        vm.expectEmit(true, false, false, true);
        emit BatchSettlement.BatchFinalized(BATCH_ID);
        vm.prank(SUBMITTER);
        settlement.submitZkBatch(BATCH_ID, RECEIPTS_ROOT, bytes32(0), RECEIPT_COUNT, address(circomAdapter), proof);
    }

    function test_submitZkBatch_rejectsDuplicate() public {
        bytes memory proof = _proofFixture();
        vm.prank(SUBMITTER);
        settlement.submitZkBatch(BATCH_ID, RECEIPTS_ROOT, bytes32(0), RECEIPT_COUNT, address(circomAdapter), proof);
        vm.prank(SUBMITTER);
        vm.expectRevert(BatchSettlement.BatchAlreadyExists.selector);
        settlement.submitZkBatch(BATCH_ID, RECEIPTS_ROOT, bytes32(0), RECEIPT_COUNT, address(circomAdapter), proof);
    }

    function test_setApprovedVerifier_onlyOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(BatchSettlement.NotOwner.selector);
        settlement.setApprovedVerifier(address(mock), true);
    }
}
