// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BatchSettlement} from "./BatchSettlement.sol";
import {ReceiptLib} from "./lib/ReceiptLib.sol";

/// @notice Receives Merkle-proof challenges against pending batches in
/// BatchSettlement. A challenge succeeds when the proven receipt violates
/// the contract-enforced charged-amount ceiling (a stand-in for a richer
/// fraud-proof predicate in future work). Successful challenges invalidate
/// the batch, slash the submitter's bond to the challenger, and decrement
/// pendingBatchesOf so the slashed submitter can no longer block their own
/// future unbond attempts.
contract DisputeManager {
    error ChallengeWindowClosed();
    error InvalidReceiptProof();
    error ChallengeFailedNoFraud();

    BatchSettlement public immutable settlement;
    uint256 public immutable chargedCeiling;

    event BatchChallenged(bytes32 indexed batchId, address indexed challenger, uint64 challengedAt);

    constructor(address settlement_, uint256 chargedCeiling_) {
        settlement = BatchSettlement(settlement_);
        chargedCeiling = chargedCeiling_;
    }

    function challengeReceipt(bytes32 batchId, ReceiptLib.Receipt calldata receipt, bytes32[] calldata proof) external {
        (
            ,
            ,
            ,
            uint64 challengeDeadline,
            ,
            BatchSettlement.BatchStatus status,
            bytes32 receiptsRoot,
            bytes32 deltasRoot
        ) = settlement.batches(batchId);
        deltasRoot;
        if (status != BatchSettlement.BatchStatus.Pending) revert ChallengeWindowClosed();
        if (block.timestamp >= challengeDeadline) revert ChallengeWindowClosed();
        bytes32 leaf = ReceiptLib.leafHash(receipt);
        if (!ReceiptLib.verifyProof(proof, receiptsRoot, leaf)) revert InvalidReceiptProof();
        if (receipt.chargedAmount <= chargedCeiling) revert ChallengeFailedNoFraud();
        emit BatchChallenged(batchId, msg.sender, uint64(block.timestamp));
        settlement.invalidateAndSlash(batchId, payable(msg.sender));
    }
}
