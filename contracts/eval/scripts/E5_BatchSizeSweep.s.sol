// code/contracts/eval/scripts/E5_BatchSizeSweep.s.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {EvalCsv} from "./lib/EvalCsv.sol";
import {PerRequestNaive} from "../../src/baselines/PerRequestNaive.sol";
import {PerRequestEventOnly} from "../../src/baselines/PerRequestEventOnly.sol";
import {SignedVoucherNetting} from "../../src/baselines/SignedVoucherNetting.sol";
import {SignedVoucherAggregate} from "../../src/baselines/SignedVoucherAggregate.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";
import {ReceiptLib} from "../../src/lib/ReceiptLib.sol";

/// @notice E5: amortized gas/call vs batch size N for the six measured systems.
/// @dev Like E4, uses raw `gasleft()` deltas around each measured call.
///      `vm.startSnapshotGas` / `vm.stopSnapshotGas` are unreliable in script
///      frame under forge 1.6+ (numbers contradict matching forge test reports),
///      so we bypass the cheatcode entirely.
contract E5_BatchSizeSweep is Script {
    string constant CSV = "./eval/data/raw/e5.csv";
    bytes32 constant BLOB_HASH = bytes32(uint256(0x01020304));
    uint256[5] BATCHES = [uint256(1), 10, 100, 1000, 5000];
    uint256[8] AGGREGATE_BATCHES = [uint256(1), 10, 50, 100, 200, 500, 1000, 5000];

    address payer     = address(0xA1);
    uint256 payerKey  = 0xA0A0;
    address submitter = address(0xC1);

    function run() external {
        EvalCsv.writeHeader(CSV, "system,batch_size,total_gas,gas_per_call");
        _sweepPerRequestNaive();
        _sweepPerRequestEventOnly();
        _sweepNetting();
        _sweepAggregate();
        _sweepTallyMesh("TallyMeshOptReceiptsOnly", false);
        _sweepTallyMesh("TallyMeshOptReceiptsPlusDeltas", true);
    }

    function _sweepPerRequestNaive() internal {
        PerRequestNaive c = new PerRequestNaive();
        vm.deal(payer, 100 ether);
        address payable r = payable(address(0xB1));
        vm.startPrank(payer);
        uint256 g0 = gasleft();
        c.pay{value: 0.001 ether}(r, keccak256("req"));
        uint256 perCall = g0 - gasleft();
        vm.stopPrank();
        for (uint256 i = 0; i < BATCHES.length; i++) {
            uint256 n = BATCHES[i];
            EvalCsv.appendRow(CSV, EvalCsv.csvRow4("PerRequestNaive", vm.toString(n), perCall * n, perCall));
        }
    }

    function _sweepPerRequestEventOnly() internal {
        PerRequestEventOnly c = new PerRequestEventOnly();
        vm.deal(payer, 100 ether);
        address payable r = payable(address(0xB2));
        vm.startPrank(payer);
        uint256 g0 = gasleft();
        c.pay{value: 0.001 ether}(r, keccak256("req"));
        uint256 perCall = g0 - gasleft();
        vm.stopPrank();
        for (uint256 i = 0; i < BATCHES.length; i++) {
            uint256 n = BATCHES[i];
            EvalCsv.appendRow(CSV, EvalCsv.csvRow4("PerRequestEventOnly", vm.toString(n), perCall * n, perCall));
        }
    }

    function _sweepNetting() internal {
        // Netting: one redeem nets N requests off-chain; on-chain cost is constant.
        // gas_per_call = redeem_gas / N.
        SignedVoucherNetting c = new SignedVoucherNetting();
        address signer = vm.addr(payerKey);
        SignedVoucherNetting.Voucher memory v = SignedVoucherNetting.Voucher({
            payer: signer,
            recipient: payable(address(0xB3)),
            sessionId: keccak256("s"),
            amount: 0.5 ether,
            nonce: 1,
            expiresAt: type(uint64).max
        });
        bytes32 digest = c.voucherDigest(v);
        (uint8 vSig, bytes32 r, bytes32 s) = vm.sign(payerKey, digest);
        bytes memory sig = abi.encodePacked(r, s, vSig);
        vm.deal(address(c), 1 ether);
        uint256 g0 = gasleft();
        c.redeem(v, sig);
        uint256 redeemGas = g0 - gasleft();
        for (uint256 i = 0; i < BATCHES.length; i++) {
            uint256 n = BATCHES[i];
            uint256 perCall = redeemGas / n;
            EvalCsv.appendRow(CSV, EvalCsv.csvRow4("SignedVoucherNetting", vm.toString(n), redeemGas, perCall));
        }
    }

    function _sweepAggregate() internal {
        // Aggregate: gas grows linearly in N (one ECDSA recover + one storage write per voucher).
        // We anchor the linear model at N=1 and N=10, then directly measure intermediate
        // points when they fit. Large N falls back to the same extrapolation.
        SignedVoucherAggregate c = new SignedVoucherAggregate();
        (bool ok1, uint256 g1) = _tryAggregateRunN(c, 1, 1);
        (bool ok10, uint256 g10) = _tryAggregateRunN(c, 10, 100);
        require(ok1 && ok10, "aggregate anchors failed");
        uint256 marginal = (g10 - g1) / 9;
        for (uint256 i = 0; i < AGGREGATE_BATCHES.length; i++) {
            uint256 n = AGGREGATE_BATCHES[i];
            uint256 total;
            if (n == 1) {
                total = g1;
            } else if (n == 10) {
                total = g10;
            } else if (n <= 500) {
                (bool ok, uint256 measured) = _tryAggregateRunN(c, n, n * 1000);
                total = ok ? measured : _extrapolateAggregate(g1, marginal, n);
            } else {
                total = _extrapolateAggregate(g1, marginal, n);
            }
            uint256 perCall = total / n;
            EvalCsv.appendRow(CSV, EvalCsv.csvRow4("SignedVoucherAggregate", vm.toString(n), total, perCall));
        }
    }

    function _tryAggregateRunN(SignedVoucherAggregate c, uint256 n, uint256 nonceStart)
        internal
        returns (bool ok, uint256 gasUsed)
    {
        SignedVoucherAggregate.Voucher[] memory vs = new SignedVoucherAggregate.Voucher[](n);
        bytes[] memory sigs = new bytes[](n);
        address signer = vm.addr(payerKey);
        for (uint256 i = 0; i < n; i++) {
            vs[i] = SignedVoucherAggregate.Voucher({
                payer: signer,
                recipient: payable(address(0xB4)),
                sessionId: keccak256(abi.encode("s", i)),
                amount: 0.0001 ether,
                nonce: nonceStart + i,
                expiresAt: type(uint64).max
            });
            (uint8 vSig, bytes32 r, bytes32 s) = vm.sign(payerKey, c.voucherDigest(vs[i]));
            sigs[i] = abi.encodePacked(r, s, vSig);
        }
        vm.deal(address(c), 100 ether);
        uint256 g0 = gasleft();
        try c.redeemBatch(vs, sigs) {
            return (true, g0 - gasleft());
        } catch {
            return (false, 0);
        }
    }

    function _extrapolateAggregate(uint256 g1, uint256 marginal, uint256 n) internal pure returns (uint256) {
        return g1 + marginal * (n - 1);
    }

    function _sweepTallyMesh(string memory system, bool withDeltas) internal {
        // For each N, deploy a fresh BatchSettlement so we always measure first-call gas.
        // submitOptimisticBatch's calldata is N-invariant (just receiptCount as a uint256),
        // so total gas should be ~constant ~142k regardless of N; gas/call = total / N.
        for (uint256 i = 0; i < BATCHES.length; i++) {
            uint256 n = BATCHES[i];
            DepositEscrow escrow = new DepositEscrow();
            BatchSettlement bs = new BatchSettlement(address(escrow));
            bs.setAuthorizedSubmitter(submitter, true);
            bs.setChallengeWindow(900);
            vm.deal(submitter, 2 ether);
            vm.startPrank(submitter);
            bs.bond{value: 1 ether}();
            bytes32 batchId = keccak256(abi.encode(system, n));
            bytes32 deltas = withDeltas ? keccak256(abi.encode("d", n)) : bytes32(0);
            _setBlobHash(BLOB_HASH);
            uint256 g0 = gasleft();
            bs.submitOptimisticBatch(batchId, keccak256(abi.encode("r", n)), deltas, n, BLOB_HASH);
            uint256 gas = g0 - gasleft();
            vm.stopPrank();
            EvalCsv.appendRow(CSV, EvalCsv.csvRow4(system, vm.toString(n), gas, gas / n));
        }
        // Per-receipt claimPayout cost. The voucher baselines redeem-and-transfer
        // atomically, so the fair end-to-end comparison is submit_gas/N + claim_gas
        // (TallyMesh) vs redeem_gas/N (voucher). Measure once for a representative
        // single-leaf batch (root == leaf hash, empty Merkle proof); per-receipt
        // cost is N-invariant (one Merkle verify + one storage write + one
        // escrow.settleReserved transfer), so we tag this row as batch_size=1 and
        // gas_per_call = total_gas to keep the CSV schema stable.
        uint256 claimGas = _measureClaim(withDeltas);
        EvalCsv.appendRow(
            CSV,
            EvalCsv.csvRow4(string.concat(system, "Claim"), "1", claimGas, claimGas)
        );
    }

    function _measureClaim(bool withDeltas) internal returns (uint256) {
        // Fresh deployment. Use a 1-second challenge window so we can warp past
        // it instantly and finalize before measuring claimPayout.
        DepositEscrow escrow = new DepositEscrow();
        BatchSettlement bs = new BatchSettlement(address(escrow));
        escrow.setAuthorizedSettler(address(bs), true);
        bs.setAuthorizedSubmitter(submitter, true);
        bs.setChallengeWindow(1);
        bs.setLegacyReserveEnabled(true);

        // Bond submitter.
        vm.deal(submitter, 2 ether);
        vm.startPrank(submitter);
        bs.bond{value: 1 ether}();
        vm.stopPrank();

        // Payer deposits and reserves session.
        // Use a unique recipient per variant so that the second measurement
        // doesn't benefit from a warm/non-empty recipient account from the
        // first run (the 25k new-account gas would otherwise be skipped).
        bytes32 sessionId = keccak256(abi.encode("claim-session", withDeltas));
        address payable recipient = payable(address(uint160(uint256(keccak256(abi.encode("claim-recipient", withDeltas))))));
        vm.deal(payer, 10 ether);
        vm.startPrank(payer);
        escrow.deposit{value: 1 ether}();
        bs.reserveSession(sessionId, recipient, 0.5 ether);
        vm.stopPrank();

        // Build a single-leaf receipt; for a single-leaf Merkle tree the root
        // equals the leaf hash and the proof is empty.
        ReceiptLib.Receipt memory receipt = ReceiptLib.Receipt({
            sessionId: sessionId,
            seq: 1,
            requestHash: keccak256("claim-req"),
            resultHash: keccak256("claim-res"),
            chargedAmount: 0.3 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        bytes32 leaf = ReceiptLib.leafHash(receipt);
        bytes32[] memory proof = new bytes32[](0);

        // Submit the optimistic batch (single receipt, leaf hash as root).
        bytes32 batchId = keccak256(abi.encode("claim-batch", withDeltas));
        bytes32 deltas = withDeltas ? keccak256("claim-deltas") : bytes32(0);
        _setBlobHash(BLOB_HASH);
        vm.prank(submitter);
        bs.submitOptimisticBatch(batchId, leaf, deltas, 1, BLOB_HASH);

        // Warp past the (1-second) challenge window and finalize.
        vm.warp(block.timestamp + 2);
        bs.finalizeBatch(batchId);

        // Measure claimPayout. No prank needed; claimPayout is permissionless.
        uint256 g0 = gasleft();
        bs.claimPayout(batchId, receipt, proof);
        uint256 gas = g0 - gasleft();
        return gas;
    }

    receive() external payable {}

    function _setBlobHash(bytes32 blobHash) internal {
        bytes32[] memory blobHashes = new bytes32[](1);
        blobHashes[0] = blobHash;
        vm.blobhashes(blobHashes);
    }
}
