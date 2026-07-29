// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IBatchVerifier} from "../interfaces/IBatchVerifier.sol";

/// @dev Generated Groth16 verifier (snarkjs export, renamed from `Groth16Verifier`).
interface IBatchValidityGroth16Verifier {
    function verifyProof(
        uint[2] calldata _pA,
        uint[2][2] calldata _pB,
        uint[2] calldata _pC,
        uint[3] calldata _pubSignals
    ) external view returns (bool);
}

/// @notice Adapts the snarkjs auto-generated Groth16 verifier for TallyMesh
/// BatchValidity to the canonical IBatchVerifier shape.
///
/// Public-input ORDER matches Circom's signal declaration order in
/// `BatchValidity.circom`: [receiptCount, chargedCeiling, receiptsRoot].
/// This is NOT the order in `component main { public [...] }`. Mismatching
/// the order will cause every verification to fail. See zk/fixtures/public.json.
///
/// `proof` is `abi.encode(uint256[2] a, uint256[2][2] b, uint256[2] c)`.
contract CircomBatchVerifier is IBatchVerifier {
    IBatchValidityGroth16Verifier public immutable groth16;

    constructor(address groth16_) {
        groth16 = IBatchValidityGroth16Verifier(groth16_);
    }

    function verifyBatch(
        bytes32 receiptsRoot,
        uint256 receiptCount,
        uint256 chargedCeiling,
        bytes calldata proof
    ) external view returns (bool) {
        (uint256[2] memory a, uint256[2][2] memory b, uint256[2] memory c) =
            abi.decode(proof, (uint256[2], uint256[2][2], uint256[2]));
        // Circom declaration order: receiptCount, chargedCeiling, receiptsRoot.
        uint[3] memory pubInput = [receiptCount, chargedCeiling, uint256(receiptsRoot)];
        return groth16.verifyProof(
            [a[0], a[1]],
            [[b[0][0], b[0][1]], [b[1][0], b[1][1]]],
            [c[0], c[1]],
            pubInput
        );
    }
}
