// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Pluggable verifier for ZK validity-proof settlement batches.
/// Implementations adapt a specific proving system (Groth16, PLONK, zkVM)
/// to the canonical (receiptsRoot, receiptCount, chargedCeiling, proof) shape.
interface IBatchVerifier {
    function verifyBatch(
        bytes32 receiptsRoot,
        uint256 receiptCount,
        uint256 chargedCeiling,
        bytes calldata proof
    ) external view returns (bool);
}
