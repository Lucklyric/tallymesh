// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CircomBatchVerifier} from "../../src/zk/CircomBatchVerifier.sol";
import {BatchValidityGroth16Verifier} from "../../src/zk/BatchValidityGroth16Verifier.sol";

contract CircomBatchVerifierTest is Test {
    CircomBatchVerifier adapter;
    BatchValidityGroth16Verifier groth16;

    // Fixture from zk/fixtures/proof.json + public.json.
    // Regenerate via: cd zk && yarn prove:fixture && yarn proof:to-solidity
    bytes32 constant RECEIPTS_ROOT = 0x10d07585399cb65d06d496c32e2246c636f436510b0637ecaf155f0ddce9f8e3;
    uint256 constant RECEIPT_COUNT = 4;
    uint256 constant CHARGED_CEILING = 1_000_000_000;

    function setUp() public {
        groth16 = new BatchValidityGroth16Verifier();
        adapter = new CircomBatchVerifier(address(groth16));
    }

    function _proofFixture() internal pure returns (bytes memory) {
        uint256[2] memory a = [
            uint256(12072786314324392949018055869985872548767102581751090816847375124952104563963),
            uint256(3073572559425341698816097753196977236977346854669974266204279780797735217849)
        ];
        uint256[2][2] memory b = [
            [uint256(21272041174551566821619849055567492274146664711343729733000831864351999110196), uint256(17063925035055354372021214682730662321888801262824471543641701803478190905230)],
            [uint256(21591639894601882780017209373616668196134517309901964898518430303059262436917), uint256(15503579737221610311205097919148761397080447087256912351236776433351967361680)]
        ];
        uint256[2] memory c = [
            uint256(12855804017717458005698454909728435589190983861447700776084435310708892950565),
            uint256(10153692300512818981466626845906469145398809320214628070824571802064466196142)
        ];
        return abi.encode(a, b, c);
    }

    function test_verifyBatch_acceptsValidProof() public view {
        bytes memory proof = _proofFixture();
        bool ok = adapter.verifyBatch(RECEIPTS_ROOT, RECEIPT_COUNT, CHARGED_CEILING, proof);
        assertTrue(ok);
    }

    function test_verifyBatch_rejectsTamperedRoot() public view {
        bytes memory proof = _proofFixture();
        bool ok = adapter.verifyBatch(bytes32(uint256(RECEIPTS_ROOT) + 1), RECEIPT_COUNT, CHARGED_CEILING, proof);
        assertFalse(ok);
    }

    function test_verifyBatch_rejectsTamperedCeiling() public view {
        bytes memory proof = _proofFixture();
        bool ok = adapter.verifyBatch(RECEIPTS_ROOT, RECEIPT_COUNT, CHARGED_CEILING + 1, proof);
        assertFalse(ok);
    }
}
