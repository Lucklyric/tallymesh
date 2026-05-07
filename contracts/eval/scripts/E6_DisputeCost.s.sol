// code/contracts/eval/scripts/E6_DisputeCost.s.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {EvalCsv} from "./lib/EvalCsv.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";
import {DisputeManager} from "../../src/DisputeManager.sol";
import {ReceiptLib} from "../../src/lib/ReceiptLib.sol";

/// @notice E6: gas cost of one valid challenge against an invalid optimistic batch.
/// @dev Two `gasleft()`-bracketed measurements: (1) submitOptimisticBatch on a
///      placeholder batch, (2) DisputeManager.challengeReceipt against a
///      single-leaf fraudulent batch where chargedAmount > chargedCeiling. For
///      a single-leaf Merkle tree, root == leafHash(receipt) and proof is the
///      empty bytes32[]. forge 1.6+ rejects address(this) as submitter in
///      script frames, so we use a separate submitter EOA + vm.startPrank.
contract E6_DisputeCost is Script {
    string constant CSV = "./eval/data/raw/e6.csv";
    bytes32 constant BLOB_HASH = bytes32(uint256(0x01020304));

    function run() external {
        EvalCsv.writeHeader(CSV, "phase,gas,latency_blocks");

        DepositEscrow escrow = new DepositEscrow();
        BatchSettlement bs = new BatchSettlement(address(escrow));
        DisputeManager dm = new DisputeManager(address(bs));
        bs.setChargedCeiling(1 ether);
        bs.setDisputeManager(address(dm));

        // forge 1.6+ rejects address(this) in scripts; use a separate submitter EOA.
        address submitter = address(0xC1);
        bs.setAuthorizedSubmitter(submitter, true);
        bs.setChallengeWindow(900);
        vm.deal(submitter, 2 ether);
        vm.startPrank(submitter);
        bs.bond{value: 1 ether}();

        // Submit a placeholder batch first to measure the submit gas line item.
        bytes32 batchId = keccak256("disputed");
        _setBlobHash(BLOB_HASH);
        uint256 g0s = gasleft();
        bs.submitOptimisticBatch(batchId, keccak256("badRoot"), bytes32(0), 1000, BLOB_HASH);
        uint256 submitGas = g0s - gasleft();
        EvalCsv.appendRow(CSV, EvalCsv.csvRow3("submit", "submitOptimisticBatch", submitGas));

        // Re-build the batch with a single fraudulent receipt so the challenger has
        // a Merkle proof to present. The DisputeManager's actual entry point is
        // `challengeReceipt(batchId, receipt, proof)` (verified against
        // contracts/src/DisputeManager.sol). For a single-leaf tree the root equals
        // ReceiptLib.leafHash(receipt) and the proof is the empty array.
        ReceiptLib.Receipt memory bad = ReceiptLib.Receipt({
            sessionId: keccak256("session-disputed"),
            seq: 1,
            requestHash: keccak256("req"),
            resultHash: keccak256("res"),
            chargedAmount: 2 ether, // > chargedCeiling = 1 ether → fraud
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        bytes32 fraudRoot = ReceiptLib.leafHash(bad);
        bytes32 fraudBatch = keccak256("disputed-2");
        _setBlobHash(BLOB_HASH);
        bs.submitOptimisticBatch(fraudBatch, fraudRoot, bytes32(0), 1, BLOB_HASH);
        vm.stopPrank();

        bytes32[] memory emptyProof = new bytes32[](0);
        address challenger = address(0xCAFE);
        vm.deal(challenger, 1 ether);
        vm.startPrank(challenger);
        uint256 g0 = gasleft();
        dm.challengeReceipt(fraudBatch, bad, emptyProof);
        uint256 challengeGas = g0 - gasleft();
        vm.stopPrank();
        EvalCsv.appendRow(CSV, EvalCsv.csvRow3("challenge", "DisputeManager.challengeReceipt", challengeGas));
    }

    receive() external payable {}

    function _setBlobHash(bytes32 blobHash) internal {
        bytes32[] memory blobHashes = new bytes32[](1);
        blobHashes[0] = blobHash;
        vm.blobhashes(blobHashes);
    }
}
