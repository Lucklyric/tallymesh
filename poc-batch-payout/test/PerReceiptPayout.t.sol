pragma solidity ^0.8.20;
import "../src/PerReceiptPayout.sol";

contract BaselineFixture is PerReceiptPayout {
    constructor() payable PerReceiptPayout(11, payable(address(22))) {}
    function markFinalForTest(bytes32 root) external { finalized[root] = true; }
}

// Same receipts as the claim-proof fixture: sequence s pays 10 or 110 units and carries payload s + 900.
// The tree is built here in Solidity and padded with zero leaves to the next power of two.
abstract contract BaselineCases {
    event log_named_uint(string key, uint256 val);
    BaselineFixture escrow;

    function size() internal pure virtual returns (uint256);

    function build(uint64 start) internal pure returns (bytes32 root, uint256 total, PerReceiptPayout.Receipt[] memory receipts) {
        uint256 count = size();
        uint256 width = 1;
        uint256 depth = 0;
        while (width < count) { width *= 2; depth++; }
        bytes32[][] memory levels = new bytes32[][](depth + 1);
        levels[0] = new bytes32[](width);
        receipts = new PerReceiptPayout.Receipt[](count);
        for (uint256 i = 0; i < count; i++) {
            uint64 sequence = start + uint64(i);
            uint64 amount = 10 + ((sequence - 1) % 2) * 100;
            bytes32 payload = bytes32(uint256(sequence) + 900);
            total += amount;
            receipts[i] = PerReceiptPayout.Receipt(sequence, amount, payload, new bytes32[](depth));
            levels[0][i] = keccak256(abi.encode(sequence, amount, payload));
        }
        for (uint256 level = 0; level < depth; level++) {
            uint256 half = levels[level].length / 2;
            levels[level + 1] = new bytes32[](half);
            for (uint256 i = 0; i < half; i++) {
                levels[level + 1][i] = keccak256(abi.encode(levels[level][2 * i], levels[level][2 * i + 1]));
            }
        }
        for (uint256 i = 0; i < count; i++) {
            for (uint256 level = 0; level < depth; level++) receipts[i].path[level] = levels[level][(i >> level) ^ 1];
        }
        root = keccak256(abi.encode(keccak256(abi.encode(uint256(11), address(22))), start, levels[depth][0]));
    }
    function attempt(bytes32 root, uint64 start, PerReceiptPayout.Receipt[] memory receipts) internal returns (bool ok) {
        (ok,) = address(escrow).call(abi.encodeCall(escrow.claim, (root, start, receipts)));
    }
    function setUp() public {
        escrow = new BaselineFixture{value: 2 * 60 * size() + 4000}();
    }

    function testClaim() public {
        (bytes32 root, uint256 total, PerReceiptPayout.Receipt[] memory receipts) = build(1);
        escrow.markFinalForTest(root);
        uint256 beforeBalance = address(22).balance;
        escrow.claim(root, 1, receipts);
        require(total == 60 * size() && address(22).balance == beforeBalance + total);
        require(escrow.paid(1) && escrow.paid(size()) && !escrow.paid(size() + 1));
    }
    // Same caveat as the claim-proof version: both claims run in one test transaction.
    function testSecondClaim() public {
        (bytes32 rootA, uint256 totalA, PerReceiptPayout.Receipt[] memory a) = build(1);
        (bytes32 rootB, uint256 totalB, PerReceiptPayout.Receipt[] memory b) = build(uint64(size()) + 1);
        escrow.markFinalForTest(rootA);
        escrow.markFinalForTest(rootB);
        escrow.claim(rootA, 1, a);
        escrow.claim(rootB, uint64(size()) + 1, b);
        require(address(22).balance == totalA + totalB && address(escrow).balance == 4000);
    }
    function testCalldataSize() public {
        (bytes32 root,, PerReceiptPayout.Receipt[] memory receipts) = build(1);
        bytes memory data = abi.encodeCall(escrow.claim, (root, 1, receipts));
        uint256 zeros;
        for (uint256 i = 0; i < data.length; i++) if (data[i] == 0) zeros++;
        emit log_named_uint("claim_calldata_bytes", data.length);
        emit log_named_uint("claim_calldata_gas_at_4_per_zero_16_per_nonzero", 4 * zeros + 16 * (data.length - zeros));
        emit log_named_uint("block_gaslimit_in_test_vm", block.gaslimit);
    }

    function testRejectRootNotFinalized() public {
        (bytes32 root,, PerReceiptPayout.Receipt[] memory receipts) = build(1);
        require(!attempt(root, 1, receipts));
        escrow.markFinalForTest(root);
        require(attempt(root, 1, receipts));
    }
    function testRejectInflatedAmount() public {
        (bytes32 root,, PerReceiptPayout.Receipt[] memory receipts) = build(1);
        escrow.markFinalForTest(root);
        receipts[0].amount += 1;
        require(!attempt(root, 1, receipts) && address(22).balance == 0);
        receipts[0].amount -= 1;
        require(attempt(root, 1, receipts));
    }
    function testRejectReplay() public {
        (bytes32 root, uint256 total, PerReceiptPayout.Receipt[] memory receipts) = build(1);
        escrow.markFinalForTest(root);
        require(attempt(root, 1, receipts));
        require(!attempt(root, 1, receipts) && address(22).balance == total);
    }
}

contract Baseline16Test is BaselineCases {
    function size() internal pure override returns (uint256) { return 16; }
}

contract Baseline64Test is BaselineCases {
    function size() internal pure override returns (uint256) { return 64; }
}

contract Baseline100Test is BaselineCases {
    function size() internal pure override returns (uint256) { return 100; }
}

contract Baseline256Test is BaselineCases {
    function size() internal pure override returns (uint256) { return 256; }
}

contract Baseline1024Test is BaselineCases {
    function size() internal pure override returns (uint256) { return 1024; }
}
