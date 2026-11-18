pragma solidity ^0.8.20;
import "../src/Payout.sol";
import "../generated/Verifier16.sol";
import "../generated/Verifier64.sol";
import "../generated/Verifier100.sol";
import "../generated/Verifier256.sol";
import "../generated/Verifier1024.sol";
import "../generated/Fixture16.sol";
import "../generated/Fixture64.sol";
import "../generated/Fixture100.sol";
import "../generated/Fixture256.sol";
import "../generated/Fixture1024.sol";

contract FinalityFixture is Payout {
    constructor(IVerifier key, uint256 batchSize) payable Payout(key, batchSize, 11, payable(address(22))) {}
    function markFinalForTest(uint256 root) external { finalized[root] = true; }
}

// One batch as the fixture gives it: sequences start .. start + size - 1.
struct Batch { uint256 root; uint256 start; uint256 total; uint256[8] proof; }

// Every rejection test breaks exactly one condition while the proof stays valid for its own statement,
// then runs the valid claim as a control. Plain Solidity, no forge-std.
abstract contract ClaimProofCases {
    event log_named_uint(string key, uint256 val);
    FinalityFixture escrow;

    function size() internal pure virtual returns (uint256);
    function deployVerifier() internal virtual returns (IVerifier);
    function first() internal pure virtual returns (Batch memory);
    function second() internal pure virtual returns (Batch memory);

    function fresh(uint256 value, bool markFinal) internal returns (FinalityFixture made) {
        made = new FinalityFixture{value: value}(deployVerifier(), size());
        if (markFinal) {
            made.markFinalForTest(first().root);
            made.markFinalForTest(second().root);
        }
    }
    function attempt(FinalityFixture target, Batch memory batch) internal returns (bool ok) {
        // Gas is capped because a malformed curve point makes the pairing precompile burn all gas it is given.
        (ok,) = address(target).call{gas: 1000000}(abi.encodeCall(target.claim, (batch.root, batch.start, batch.total, batch.proof)));
    }
    function rejected(FinalityFixture target, Batch memory batch) internal returns (bool) {
        uint256 balance = address(target).balance;
        return !attempt(target, batch) && target.next() == 1 && address(target).balance == balance;
    }
    function setUp() public {
        escrow = fresh(first().total + second().total + 4000, true);
    }

    function testClaim() public {
        Batch memory batch = first();
        uint256 beforeBalance = address(22).balance;
        escrow.claim(batch.root, batch.start, batch.total, batch.proof);
        require(address(22).balance == beforeBalance + batch.total && address(escrow).balance == second().total + 4000);
        require(escrow.next() == size() + 1);
    }
    // The second claim runs in the same test transaction as the first, so the cursor slot,
    // the verifier and the recipient are already warm, and the recipient account already exists.
    function testSecondClaim() public {
        Batch memory a = first();
        Batch memory b = second();
        escrow.claim(a.root, a.start, a.total, a.proof);
        escrow.claim(b.root, b.start, b.total, b.proof);
        require(address(22).balance == a.total + b.total && address(escrow).balance == 4000);
        require(escrow.next() == 2 * size() + 1);
    }
    function testCalldataSize() public {
        Batch memory batch = first();
        bytes memory data = abi.encodeCall(escrow.claim, (batch.root, batch.start, batch.total, batch.proof));
        uint256 zeros;
        for (uint256 i = 0; i < data.length; i++) if (data[i] == 0) zeros++;
        emit log_named_uint("claim_calldata_bytes", data.length);
        emit log_named_uint("claim_calldata_gas_at_4_per_zero_16_per_nonzero", 4 * zeros + 16 * (data.length - zeros));
        emit log_named_uint("block_gaslimit_in_test_vm", block.gaslimit);
    }

    function testRejectRootNotFinalized() public {
        FinalityFixture pending = fresh(first().total, false);
        require(rejected(pending, first()));
        pending.markFinalForTest(first().root);
        require(attempt(pending, first()));
    }
    function testRejectWrongStart() public {
        // Valid proof and finalized root for the second batch, but the cursor is still at 1.
        require(rejected(escrow, second()));
        require(attempt(escrow, first()) && attempt(escrow, second()));
    }
    function testRejectTotalAboveBalance() public {
        FinalityFixture poor = fresh(first().total - 1, true);
        require(rejected(poor, first()));
        require(attempt(escrow, first()));
    }
    function testRejectInflatedTotal() public {
        Batch memory batch = first();
        batch.total += 1;
        require(batch.total <= address(escrow).balance && rejected(escrow, batch));
        require(attempt(escrow, first()));
    }
    function testRejectTamperedProofWord() public {
        for (uint256 word = 0; word < 8; word++) {
            Batch memory batch = first();
            batch.proof[word] ^= 1;
            require(rejected(escrow, batch));
        }
        require(attempt(escrow, first()));
    }
    function testRejectReplay() public {
        require(attempt(escrow, first()));
        uint256 balance = address(escrow).balance;
        require(!attempt(escrow, first()));
        require(escrow.next() == size() + 1 && address(escrow).balance == balance);
    }
}

contract ClaimProof16Test is ClaimProofCases {
    function size() internal pure override returns (uint256) { return 16; }
    function deployVerifier() internal override returns (IVerifier) { return IVerifier(address(new Verifier16())); }
    function first() internal pure override returns (Batch memory) { return Batch(Fixture16.ROOT, 1, Fixture16.TOTAL, Fixture16.proof()); }
    function second() internal pure override returns (Batch memory) { return Batch(Fixture16.ROOT2, 16 + 1, Fixture16.TOTAL2, Fixture16.proof2()); }
}

contract ClaimProof64Test is ClaimProofCases {
    function size() internal pure override returns (uint256) { return 64; }
    function deployVerifier() internal override returns (IVerifier) { return IVerifier(address(new Verifier64())); }
    function first() internal pure override returns (Batch memory) { return Batch(Fixture64.ROOT, 1, Fixture64.TOTAL, Fixture64.proof()); }
    function second() internal pure override returns (Batch memory) { return Batch(Fixture64.ROOT2, 64 + 1, Fixture64.TOTAL2, Fixture64.proof2()); }
}

contract ClaimProof100Test is ClaimProofCases {
    function size() internal pure override returns (uint256) { return 100; }
    function deployVerifier() internal override returns (IVerifier) { return IVerifier(address(new Verifier100())); }
    function first() internal pure override returns (Batch memory) { return Batch(Fixture100.ROOT, 1, Fixture100.TOTAL, Fixture100.proof()); }
    function second() internal pure override returns (Batch memory) { return Batch(Fixture100.ROOT2, 100 + 1, Fixture100.TOTAL2, Fixture100.proof2()); }
}

contract ClaimProof256Test is ClaimProofCases {
    function size() internal pure override returns (uint256) { return 256; }
    function deployVerifier() internal override returns (IVerifier) { return IVerifier(address(new Verifier256())); }
    function first() internal pure override returns (Batch memory) { return Batch(Fixture256.ROOT, 1, Fixture256.TOTAL, Fixture256.proof()); }
    function second() internal pure override returns (Batch memory) { return Batch(Fixture256.ROOT2, 256 + 1, Fixture256.TOTAL2, Fixture256.proof2()); }
}

contract ClaimProof1024Test is ClaimProofCases {
    function size() internal pure override returns (uint256) { return 1024; }
    function deployVerifier() internal override returns (IVerifier) { return IVerifier(address(new Verifier1024())); }
    function first() internal pure override returns (Batch memory) { return Batch(Fixture1024.ROOT, 1, Fixture1024.TOTAL, Fixture1024.proof()); }
    function second() internal pure override returns (Batch memory) { return Batch(Fixture1024.ROOT2, 1024 + 1, Fixture1024.TOTAL2, Fixture1024.proof2()); }
}
