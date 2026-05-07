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
    bytes32 constant RECEIPTS_ROOT = 0x10db92868d4ee7a08981b320f8a3a9b05d5740307992f3d11db2bf563a06fbbb;
    uint256 constant RECEIPT_COUNT = 4;
    uint256 constant CHARGED_CEILING = 1_000_000_000;

    function setUp() public {
        groth16 = new BatchValidityGroth16Verifier();
        adapter = new CircomBatchVerifier(address(groth16));
    }

    function _proofFixture() internal pure returns (bytes memory) {
        uint256[2] memory a = [
            uint256(16512046622187174188098503585132137504582541678270766737182804156567877185334),
            uint256(9875097695020730075130571040372152364961047659618248542301431011823075973112)
        ];
        uint256[2][2] memory b = [
            [uint256(6297386241683868973207937054561845949342059436507685812473297926799933011317), uint256(12609879225805945340229132194806303329823443956226206464286143915125350923519)],
            [uint256(6672819003095191309479166958040846794084840363370343187592718941826630790598), uint256(4517532005546784128615258124180779773674465725660750988798187680940330819587)]
        ];
        uint256[2] memory c = [
            uint256(6019492291923717747846810560477057442965076607799104829075879954677170212693),
            uint256(2612078083830093103957591592452032346173577789978769854891055469195624034723)
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
