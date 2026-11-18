pragma solidity ^0.8.20;

// Each batch size has its own generated Groth16 verifier, so the escrow only names the call it needs.
interface IVerifier {
    function verifyProof(uint256[8] calldata proof, uint256[5] calldata input) external view;
}

contract Payout {
    IVerifier immutable verifier;
    uint256 immutable session;
    address payable immutable provider;
    uint256 immutable count;
    uint256 public next = 1;
    mapping(uint256 => bool) public finalized;

    constructor(IVerifier key, uint256 batchSize, uint256 sessionId, address payable recipient) payable {
        verifier = key;
        count = batchSize;
        session = sessionId;
        provider = recipient;
    }

    function claim(uint256 root, uint256 start, uint256 total, uint256[8] calldata proof) external {
        require(finalized[root] && start == next && total <= address(this).balance);
        verifier.verifyProof(proof, [root, session, uint256(uint160(address(provider))), start, total]);
        next += count;
        (bool ok,) = provider.call{value: total}("");
        require(ok);
    }
}
