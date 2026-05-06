pragma circom 2.1.8;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";
include "PoseidonMerkleRoot.circom";

/// @dev TallyMesh batch validity circuit (v1).
///
/// For private inputs `chargedAmounts[N]` and `leafTags[N]` (zero for inactive slots)
/// and public inputs `(receiptsRoot, receiptCount, chargedCeiling)`, prove:
///   (a) PoseidonMerkleRoot(leafEncodings) == receiptsRoot, where
///       leafEncoding[i] = i < receiptCount ? Poseidon([chargedAmount[i], leafTag[i]]) : 0
///   (b) chargedAmount[i] <= chargedCeiling for all i < receiptCount
///   (c) chargedAmount[i] == 0 and leafTag[i] == 0 for all i >= receiptCount (padding)
///
/// `N = 2^DEPTH = 1024` for v1. CEILING_BITS = 64 means chargedAmount fits in uint64.

template BatchValidity(DEPTH, CEILING_BITS) {
    var N = 1 << DEPTH;

    signal input chargedAmounts[N];
    signal input leafTags[N];
    signal input receiptCount;
    signal input chargedCeiling;
    signal input receiptsRoot;

    // (a) Compute leaf encodings.
    component leafHashers[N];
    component activeLte[N];
    signal leafEncodings[N];
    for (var i = 0; i < N; i++) {
        // active = (i < receiptCount)
        activeLte[i] = LessThan(DEPTH + 1);
        activeLte[i].in[0] <== i;
        activeLte[i].in[1] <== receiptCount;
        // leafEncoding = active ? Poseidon([chargedAmount, tag]) : 0
        leafHashers[i] = Poseidon(2);
        leafHashers[i].inputs[0] <== chargedAmounts[i];
        leafHashers[i].inputs[1] <== leafTags[i];
        leafEncodings[i] <== activeLte[i].out * leafHashers[i].out;
    }

    // (a) Compute Poseidon Merkle root.
    component merkle = PoseidonMerkleRoot(DEPTH);
    for (var i = 0; i < N; i++) {
        merkle.leaves[i] <== leafEncodings[i];
    }
    merkle.root === receiptsRoot;

    // (b) Bounds check on active slots.
    component ceilingLte[N];
    for (var i = 0; i < N; i++) {
        ceilingLte[i] = LessEqThan(CEILING_BITS);
        ceilingLte[i].in[0] <== chargedAmounts[i];
        ceilingLte[i].in[1] <== chargedCeiling;
        // For inactive slots, chargedAmount == 0 (forced by step c), so the LessEqThan is trivially true.
        // For active slots, we require the LessEqThan to hold.
        activeLte[i].out * (1 - ceilingLte[i].out) === 0;
    }

    // (c) Padding constraint: inactive slot fields must be zero.
    for (var i = 0; i < N; i++) {
        (1 - activeLte[i].out) * chargedAmounts[i] === 0;
        (1 - activeLte[i].out) * leafTags[i] === 0;
    }
}

component main { public [receiptsRoot, receiptCount, chargedCeiling] } = BatchValidity(10, 64);
