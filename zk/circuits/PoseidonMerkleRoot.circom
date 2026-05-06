pragma circom 2.1.8;

include "../node_modules/circomlib/circuits/poseidon.circom";

/// @dev Computes a Poseidon Merkle root over an array of `2**depth` field elements.
/// Arity = 2. Each parent = Poseidon([left, right]).
template PoseidonMerkleRoot(depth) {
    var n = 1 << depth;
    signal input leaves[n];
    signal output root;

    var nodeCount = 2 * n - 1;
    component hashers[n - 1];
    signal nodes[nodeCount];

    // Leaves at indices [n-1 .. 2n-2]
    for (var i = 0; i < n; i++) {
        nodes[n - 1 + i] <== leaves[i];
    }

    // Internal nodes [0 .. n-2]
    for (var i = n - 2; i >= 0; i--) {
        hashers[i] = Poseidon(2);
        hashers[i].inputs[0] <== nodes[2 * i + 1];
        hashers[i].inputs[1] <== nodes[2 * i + 2];
        nodes[i] <== hashers[i].out;
    }

    root <== nodes[0];
}
