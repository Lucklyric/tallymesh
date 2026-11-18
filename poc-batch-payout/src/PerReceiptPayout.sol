pragma solidity ^0.8.20;

// Our own baseline for the same harness: no proof system, the contract checks every receipt.
// Same asset (native wei), one session, one provider, same finalized-root gate as Payout.
// This is not the contract measured in the paper.
contract PerReceiptPayout {
    struct Receipt {
        uint64 sequence;
        uint64 amount;
        bytes32 payload;
        bytes32[] path;
    }

    uint256 immutable session;
    address payable immutable provider;
    mapping(bytes32 => bool) public finalized;
    mapping(uint256 => bool) public paid;

    constructor(uint256 sessionId, address payable recipient) payable {
        session = sessionId;
        provider = recipient;
    }

    // Leaf i (0-based) of a binary Keccak tree holds the receipt with sequence first + i.
    // The finalized root binds session and provider to the tree root, as in the claim-proof design.
    function claim(bytes32 root, uint64 first, Receipt[] calldata receipts) external {
        require(finalized[root]);
        bytes32 scope = keccak256(abi.encode(session, provider));
        uint256 total;
        for (uint256 i = 0; i < receipts.length; i++) {
            Receipt calldata receipt = receipts[i];
            bytes32 node = keccak256(abi.encode(receipt.sequence, receipt.amount, receipt.payload));
            uint256 position = receipt.sequence - first;
            for (uint256 level = 0; level < receipt.path.length; level++) {
                bytes32 sibling = receipt.path[level];
                node = position & 1 == 0 ? keccak256(abi.encode(node, sibling)) : keccak256(abi.encode(sibling, node));
                position >>= 1;
            }
            require(position == 0 && keccak256(abi.encode(scope, first, node)) == root);
            require(!paid[receipt.sequence]);
            paid[receipt.sequence] = true;
            total += receipt.amount;
        }
        require(total <= address(this).balance);
        (bool ok,) = provider.call{value: total}("");
        require(ok);
    }
}
