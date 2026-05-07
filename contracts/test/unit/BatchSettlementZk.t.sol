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
    bytes32 constant RECEIPTS_ROOT = 0x10db92868d4ee7a08981b320f8a3a9b05d5740307992f3d11db2bf563a06fbbb;
    uint256 constant RECEIPT_COUNT = 4;
    uint256 constant CHARGED_CEILING = 1_000_000_000;

    function _proofFixture() internal pure returns (bytes memory) {
        uint256[2] memory a = [
            uint256(16512046622187174188098503585132137504582541678270766737182804156567877185334),
            uint256(9875097695020730075130571040372152364961047659618248542301431011823075973112)
        ];
        uint256[2][2] memory b = [
            [uint256(6297386241683868973207937054561845949342059436507685812473297926799933011317), uint256(12609879225805945340229132194806303329823443956226206464286143915125350923519)],
            [uint256(6672819003095191309479166958040846794084840363370343187592718941826630790598), uint256(4517532005546784128615258124180779773674465725660750988798187680940330819587)]
        ];
        uint256[2] memory c = [
            uint256(6019492291923717747846810560477057442965076607799104829075879954677170212693),
            uint256(2612078083830093103957591592452032346173577789978769854891055469195624034723)
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
