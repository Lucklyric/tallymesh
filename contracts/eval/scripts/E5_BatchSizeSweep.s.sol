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

/// @notice E5: amortized gas/call vs batch size N for the six measured systems.
/// @dev Like E4, uses raw `gasleft()` deltas around each measured call.
///      `vm.startSnapshotGas` / `vm.stopSnapshotGas` are unreliable in script
///      frame under forge 1.6+ (numbers contradict matching forge test reports),
///      so we bypass the cheatcode entirely.
contract E5_BatchSizeSweep is Script {
    string constant CSV = "./eval/data/raw/e5.csv";
    uint256[5] BATCHES = [uint256(1), 10, 100, 1000, 5000];

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
        // We measure N=1 and N=10 and linearly extrapolate. For large N (1000, 5000) the
        // contract call would exceed Anvil block gas; the linear model captures the same shape.
        SignedVoucherAggregate c = new SignedVoucherAggregate();
        uint256 g1 = _aggregateRunN(c, 1, 1);
        uint256 g10 = _aggregateRunN(c, 10, 100);
        uint256 marginal = (g10 - g1) / 9;
        for (uint256 i = 0; i < BATCHES.length; i++) {
            uint256 n = BATCHES[i];
            uint256 total = g1 + marginal * (n - 1);
            uint256 perCall = total / n;
            EvalCsv.appendRow(CSV, EvalCsv.csvRow4("SignedVoucherAggregate", vm.toString(n), total, perCall));
        }
    }

    function _aggregateRunN(SignedVoucherAggregate c, uint256 n, uint256 nonceStart) internal returns (uint256) {
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
        c.redeemBatch(vs, sigs);
        return g0 - gasleft();
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
            uint256 g0 = gasleft();
            bs.submitOptimisticBatch(batchId, keccak256(abi.encode("r", n)), deltas, n);
            uint256 gas = g0 - gasleft();
            vm.stopPrank();
            EvalCsv.appendRow(CSV, EvalCsv.csvRow4(system, vm.toString(n), gas, gas / n));
        }
    }

    receive() external payable {}
}
