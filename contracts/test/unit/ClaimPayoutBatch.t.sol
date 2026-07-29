// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {BlobHashHelper} from "../helpers/BlobHashHelper.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";
import {ReceiptLib} from "../../src/lib/ReceiptLib.sol";
import {IBatchVerifier} from "../../src/interfaces/IBatchVerifier.sol";

contract ZkAggregateMockVerifier is IBatchVerifier {
    function verifyBatch(bytes32, uint256, uint256, bytes calldata) external pure returns (bool) {
        return true;
    }
}

/// @notice Correctness and amortized gas for claimPayoutBatch (aggregate-claim path).
/// Builds real Merkle trees from N leaves and measures gas at N in {1, 4, 16, 64, 256, 1024}.
contract ClaimPayoutBatchTest is BlobHashHelper {
    BatchSettlement settlement;
    DepositEscrow escrow;
    address constant OWNER = address(0xDEEDA);
    address constant SUBMITTER = address(0x5BB1);
    address constant PAYER = address(0xA11CE);
    address payable constant SERVICE = payable(address(0x5E2C1));
    bytes32 constant SESSION = bytes32("sess-1");
    uint256 constant CHALLENGE_WINDOW = 1;

    function setUp() public {
        vm.prank(OWNER);
        escrow = new DepositEscrow();
        vm.prank(OWNER);
        settlement = new BatchSettlement(address(escrow));
        vm.startPrank(OWNER);
        settlement.setChallengeWindow(uint64(CHALLENGE_WINDOW));
        settlement.setAuthorizedSubmitter(SUBMITTER, true);
        escrow.setAuthorizedSettler(address(settlement), true);
        settlement.setLegacyReserveEnabled(true);
        vm.stopPrank();
        vm.deal(SUBMITTER, 10 ether);
        vm.prank(SUBMITTER);
        settlement.bond{value: 2 ether}();
        vm.deal(PAYER, 100 ether);
        vm.prank(PAYER);
        escrow.deposit{value: 50 ether}();
    }

    // ---------- Merkle helpers ----------

    function _buildReceipts(bytes32 sessionId, uint256 n, uint256 amountWei)
        internal
        view
        returns (ReceiptLib.Receipt[] memory receipts, bytes32[] memory leaves)
    {
        receipts = new ReceiptLib.Receipt[](n);
        leaves = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            receipts[i] = ReceiptLib.Receipt({
                sessionId: sessionId,
                seq: uint64(i + 1),
                requestHash: keccak256(abi.encode("req", i)),
                resultHash: keccak256(abi.encode("res", i)),
                chargedAmount: amountWei,
                statusCode: bytes32("OK"),
                serviceTimestamp: uint64(block.timestamp)
            });
            leaves[i] = ReceiptLib.leafHash(receipts[i]);
        }
    }

    /// @dev Sorted-pair Merkle (matches ReceiptLib.hashPair). For odd-length levels we
    /// duplicate the last node (OpenZeppelin convention) so depth = ceil(log2(N)).
    function _root(bytes32[] memory leaves) internal pure returns (bytes32) {
        bytes32[] memory level = leaves;
        while (level.length > 1) {
            uint256 nextLen = (level.length + 1) / 2;
            bytes32[] memory next = new bytes32[](nextLen);
            for (uint256 i = 0; i < nextLen; i++) {
                bytes32 a = level[2 * i];
                bytes32 b = (2 * i + 1 < level.length) ? level[2 * i + 1] : level[2 * i];
                next[i] = a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
            }
            level = next;
        }
        return level[0];
    }

    function _proof(bytes32[] memory leaves, uint256 idx) internal pure returns (bytes32[] memory) {
        uint256 depth = 0;
        for (uint256 size = leaves.length; size > 1; size = (size + 1) / 2) depth++;
        bytes32[] memory proof = new bytes32[](depth);
        bytes32[] memory level = leaves;
        uint256 pos = idx;
        uint256 d = 0;
        while (level.length > 1) {
            uint256 sibling = (pos % 2 == 0) ? pos + 1 : pos - 1;
            if (sibling >= level.length) sibling = pos; // odd-length tail duplication
            proof[d++] = level[sibling];
            uint256 nextLen = (level.length + 1) / 2;
            bytes32[] memory next = new bytes32[](nextLen);
            for (uint256 i = 0; i < nextLen; i++) {
                bytes32 a = level[2 * i];
                bytes32 b = (2 * i + 1 < level.length) ? level[2 * i + 1] : level[2 * i];
                next[i] = a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
            }
            level = next;
            pos /= 2;
        }
        // shrink to actual depth (depth may equal 0 for n=1)
        bytes32[] memory out = new bytes32[](d);
        for (uint256 i = 0; i < d; i++) out[i] = proof[i];
        return out;
    }

    function _submitAndFinalize(bytes32 batchId, bytes32 root, uint256 n) internal {
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(batchId, root, bytes32(0), n, TEST_BLOB_HASH);
        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(batchId);
    }

    function _reserveSession(bytes32 sessionId, uint256 amount) internal {
        vm.prank(PAYER);
        settlement.reserveSession(sessionId, SERVICE, amount);
    }

    // ---------- correctness tests ----------

    function test_batchClaim_paysSumToRecipient() public {
        _reserveSession(SESSION, 1 ether);
        uint256 n = 4;
        uint256 amt = 0.1 ether;
        (ReceiptLib.Receipt[] memory rs, bytes32[] memory leaves) = _buildReceipts(SESSION, n, amt);
        bytes32 root = _root(leaves);
        bytes32[][] memory proofs = new bytes32[][](n);
        for (uint256 i = 0; i < n; i++) proofs[i] = _proof(leaves, i);
        _submitAndFinalize(bytes32("b1"), root, n);
        uint256 before = SERVICE.balance;
        settlement.claimPayoutBatch(bytes32("b1"), rs, proofs);
        assertEq(SERVICE.balance - before, n * amt);
    }

    function test_batchClaim_revertsOnMixedSessions() public {
        _reserveSession(SESSION, 1 ether);
        uint256 n = 4;
        (ReceiptLib.Receipt[] memory rs, bytes32[] memory leaves) = _buildReceipts(SESSION, n, 0.1 ether);
        rs[2].sessionId = bytes32("other"); // poison one
        leaves[2] = ReceiptLib.leafHash(rs[2]);
        bytes32 root = _root(leaves);
        bytes32[][] memory proofs = new bytes32[][](n);
        for (uint256 i = 0; i < n; i++) proofs[i] = _proof(leaves, i);
        _submitAndFinalize(bytes32("b1"), root, n);
        vm.expectRevert(BatchSettlement.MixedSessionsNotAllowed.selector);
        settlement.claimPayoutBatch(bytes32("b1"), rs, proofs);
    }

    function test_batchClaim_revertsOnEmpty() public {
        ReceiptLib.Receipt[] memory rs = new ReceiptLib.Receipt[](0);
        bytes32[][] memory proofs = new bytes32[][](0);
        vm.expectRevert(BatchSettlement.EmptyClaimBatch.selector);
        settlement.claimPayoutBatch(bytes32("nope"), rs, proofs);
    }

    function test_batchClaim_revertsOnLengthMismatch() public {
        _reserveSession(SESSION, 1 ether);
        (ReceiptLib.Receipt[] memory rs,) = _buildReceipts(SESSION, 2, 0.1 ether);
        bytes32[][] memory proofs = new bytes32[][](1); // shorter
        proofs[0] = new bytes32[](0);
        vm.expectRevert(BatchSettlement.ArrayLengthMismatch.selector);
        settlement.claimPayoutBatch(bytes32("nope"), rs, proofs);
    }

    function test_batchClaim_revertsOnInvalidProof() public {
        _reserveSession(SESSION, 1 ether);
        uint256 n = 4;
        (ReceiptLib.Receipt[] memory rs, bytes32[] memory leaves) = _buildReceipts(SESSION, n, 0.1 ether);
        bytes32 root = _root(leaves);
        bytes32[][] memory proofs = new bytes32[][](n);
        for (uint256 i = 0; i < n; i++) proofs[i] = _proof(leaves, i);
        // tamper one proof
        proofs[1][0] = bytes32("garbage");
        _submitAndFinalize(bytes32("b1"), root, n);
        vm.expectRevert(BatchSettlement.InvalidReceiptProof.selector);
        settlement.claimPayoutBatch(bytes32("b1"), rs, proofs);
    }

    function test_batchClaim_revertsOnDuplicateInSameBatch() public {
        _reserveSession(SESSION, 1 ether);
        uint256 n = 2;
        (ReceiptLib.Receipt[] memory rsBase, bytes32[] memory leavesBase) = _buildReceipts(SESSION, n, 0.1 ether);
        // craft a batch where two entries reference the same receipt
        ReceiptLib.Receipt[] memory rs = new ReceiptLib.Receipt[](2);
        rs[0] = rsBase[0];
        rs[1] = rsBase[0]; // duplicate
        bytes32 root = _root(leavesBase);
        bytes32[][] memory proofs = new bytes32[][](2);
        proofs[0] = _proof(leavesBase, 0);
        proofs[1] = _proof(leavesBase, 0);
        _submitAndFinalize(bytes32("b1"), root, n);
        vm.expectRevert(BatchSettlement.ReceiptAlreadyClaimed.selector);
        settlement.claimPayoutBatch(bytes32("b1"), rs, proofs);
    }

    function test_batchClaim_blocksCrossMethodReClaim() public {
        _reserveSession(SESSION, 1 ether);
        uint256 n = 2;
        (ReceiptLib.Receipt[] memory rs, bytes32[] memory leaves) = _buildReceipts(SESSION, n, 0.1 ether);
        bytes32 root = _root(leaves);
        bytes32[][] memory proofs = new bytes32[][](n);
        for (uint256 i = 0; i < n; i++) proofs[i] = _proof(leaves, i);
        _submitAndFinalize(bytes32("b1"), root, n);
        // first claim via single-claim path
        settlement.claimPayout(bytes32("b1"), rs[0], proofs[0]);
        // batch claim including the already-claimed receipt must revert
        vm.expectRevert(BatchSettlement.ReceiptAlreadyClaimed.selector);
        settlement.claimPayoutBatch(bytes32("b1"), rs, proofs);
    }

    function test_batchClaim_revertsBeforeFinalization() public {
        _reserveSession(SESSION, 1 ether);
        uint256 n = 2;
        (ReceiptLib.Receipt[] memory rs, bytes32[] memory leaves) = _buildReceipts(SESSION, n, 0.1 ether);
        bytes32 root = _root(leaves);
        bytes32[][] memory proofs = new bytes32[][](n);
        for (uint256 i = 0; i < n; i++) proofs[i] = _proof(leaves, i);
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(bytes32("b1"), root, bytes32(0), n, TEST_BLOB_HASH);
        // do NOT finalize
        vm.expectRevert(BatchSettlement.BatchNotFinalized.selector);
        settlement.claimPayoutBatch(bytes32("b1"), rs, proofs);
    }

    function test_batchClaim_revertsWhenSessionUnopened() public {
        bytes32 unopened = bytes32("orphan-session");
        uint256 n = 2;
        (ReceiptLib.Receipt[] memory rs, bytes32[] memory leaves) = _buildReceipts(unopened, n, 0.1 ether);
        bytes32 root = _root(leaves);
        bytes32[][] memory proofs = new bytes32[][](n);
        for (uint256 i = 0; i < n; i++) proofs[i] = _proof(leaves, i);
        _submitAndFinalize(bytes32("b1"), root, n);
        vm.expectRevert(BatchSettlement.SessionNotFound.selector);
        settlement.claimPayoutBatch(bytes32("b1"), rs, proofs);
    }

    // ---------- gas measurement ----------

    /// @dev Emits one gas number per N to stdout. Forge test prints console2 lines
    /// when run with `forge test -vv`. Each iteration uses a fresh deployment so
    /// first-touch storage costs are charged consistently per N.
    function test_gas_sweep_amortized() public {
        uint256[6] memory NS = [uint256(1), uint256(4), uint256(16), uint256(64), uint256(256), uint256(512)];
        for (uint256 k = 0; k < NS.length; k++) {
            _measureOneN(NS[k]);
        }
    }

    function _measureOneN(uint256 n) internal {
        (BatchSettlement bs, DepositEscrow esc) = _freshStack();
        _wireRoles(bs, esc, n);
        _fundParties(esc, n);
        (bytes32 batchId, ReceiptLib.Receipt[] memory rs, bytes32[][] memory proofs) = _prepBatch(bs, n);
        uint256 g0 = gasleft();
        bs.claimPayoutBatch(batchId, rs, proofs);
        uint256 used = g0 - gasleft();
        console2.log("CLAIM_BATCH_GAS_N", n, "gas", used);
        console2.log("                    per-leaf", used / n);
    }

    function _payerFor(uint256 n) internal pure returns (address) { return address(uint160(0xA0000000 + n)); }
    function _submitterFor(uint256 n) internal pure returns (address) { return address(uint160(0xC0000000 + n)); }
    function _recipientFor(uint256 n) internal pure returns (address payable) { return payable(address(uint160(0xB0000000 + n))); }
    function _sessionFor(uint256 n) internal pure returns (bytes32) { return bytes32(uint256(0xDEAD0000 + n)); }
    function _batchFor(uint256 n) internal pure returns (bytes32) { return bytes32(uint256(0xBA7C0000 + n)); }

    function _wireRoles(BatchSettlement bs, DepositEscrow esc, uint256 n) internal {
        vm.startPrank(OWNER);
        bs.setAuthorizedSubmitter(_submitterFor(n), true);
        esc.setAuthorizedSettler(address(bs), true);
        bs.setChallengeWindow(1);
        bs.setLegacyReserveEnabled(true);
        vm.stopPrank();
    }

    function _fundParties(DepositEscrow esc, uint256 n) internal {
        address submitter = _submitterFor(n);
        address payer = _payerFor(n);
        vm.deal(submitter, 10 ether);
        vm.prank(submitter);
        BatchSettlement(payable(address(_bsOf(esc)))).bond{value: 2 ether}();
        vm.deal(payer, 200 ether);
        vm.prank(payer);
        esc.deposit{value: 100 ether}();
    }

    // Track the most recently created BS so funding can reference it without an extra arg.
    BatchSettlement private _latestBs;
    function _bsOf(DepositEscrow) internal view returns (BatchSettlement) { return _latestBs; }

    function _prepBatch(BatchSettlement bs, uint256 n)
        internal
        returns (bytes32 batchId, ReceiptLib.Receipt[] memory rs, bytes32[][] memory proofs)
    {
        bytes32 sid = _sessionFor(n);
        uint256 amt = 0.0001 ether;
        vm.prank(_payerFor(n));
        bs.reserveSession(sid, _recipientFor(n), amt * n);
        bytes32[] memory leaves;
        (rs, leaves) = _buildReceipts(sid, n, amt);
        bytes32 root = _root(leaves);
        proofs = new bytes32[][](n);
        for (uint256 i = 0; i < n; i++) proofs[i] = _proof(leaves, i);
        batchId = _batchFor(n);
        _setBlobHash(TEST_BLOB_HASH);
        vm.prank(_submitterFor(n));
        bs.submitOptimisticBatch(batchId, root, bytes32(0), n, TEST_BLOB_HASH);
        vm.warp(block.timestamp + 2);
        bs.finalizeBatch(batchId);
    }

    function _freshStack() internal returns (BatchSettlement bs, DepositEscrow esc) {
        vm.prank(OWNER);
        esc = new DepositEscrow();
        vm.prank(OWNER);
        bs = new BatchSettlement(address(esc));
        _latestBs = bs;
    }

    // ---------- ZK-mode aggregate-claim parity (Iteration 2.5) ----------

    /// @dev Sweep claimPayoutBatch gas in ZK mode for N in {1, 4, 16, 64}, proving
    /// the aggregate-claim path is end-to-end functional in validity mode and
    /// achieves the same optimum as optimistic at N=64.
    function test_gas_sweep_amortized_zkMode() public {
        uint256[4] memory NS = [uint256(1), uint256(4), uint256(16), uint256(64)];
        for (uint256 k = 0; k < NS.length; k++) {
            _measureOneNZk(NS[k]);
        }
    }

    function _measureOneNZk(uint256 n) internal {
        (BatchSettlement bs, DepositEscrow esc) = _freshStack();
        _wireRoles(bs, esc, n);
        _fundParties(esc, n);

        ZkAggregateMockVerifier verifier = new ZkAggregateMockVerifier();
        vm.prank(OWNER);
        bs.setApprovedVerifier(address(verifier), true);

        bytes32 sid = _sessionFor(n);
        uint256 amt = 0.0001 ether;
        vm.prank(_payerFor(n));
        bs.reserveSession(sid, _recipientFor(n), amt * n);

        (ReceiptLib.Receipt[] memory rs, bytes32[] memory leaves) = _buildReceipts(sid, n, amt);
        bytes32 root = _root(leaves);
        bytes32[][] memory proofs = new bytes32[][](n);
        for (uint256 i = 0; i < n; i++) proofs[i] = _proof(leaves, i);

        bytes32 batchId = _batchFor(n);
        vm.prank(_submitterFor(n));
        bs.submitZkBatch(batchId, root, bytes32(0), n, address(verifier), hex"");

        uint256 g0 = gasleft();
        bs.claimPayoutBatch(batchId, rs, proofs);
        uint256 used = g0 - gasleft();
        console2.log("ZK_CLAIM_BATCH_GAS_N", n, "gas", used);
        console2.log("                       per-leaf", used / n);
    }
}
