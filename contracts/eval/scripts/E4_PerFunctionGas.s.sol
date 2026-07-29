// code/contracts/eval/scripts/E4_PerFunctionGas.s.sol
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

/// @notice E4: opcode-gas per happy-path entry point on each of the six measured systems.
/// @dev Uses raw `gasleft()` deltas around each call. `vm.startSnapshotGas` /
///      `vm.stopSnapshotGas` produced inverted/inflated numbers under forge 1.6
///      script frames (e.g., EventOnly > Naive, TallyMesh first-call > 2M),
///      contradicting the matching forge test gas reports. `gasleft()` bypasses
///      the cheatcode entirely and gives raw EVM gas accounting around the call.
contract E4_PerFunctionGas is Script {
    string constant CSV = "./eval/data/raw/e4.csv";
    bytes32 constant BLOB_HASH = bytes32(uint256(0x01020304));

    address payer     = address(0xA1);
    uint256 payerKey  = 0xA0A0;
    address submitter = address(0xC1);

    function run() external {
        EvalCsv.writeHeader(CSV, "system,function,gas");
        _measurePerRequestNaive();
        _measurePerRequestEventOnly();
        _measureSignedVoucherNetting();
        _measureSignedVoucherAggregate();
        _measureTallyMeshReceiptsOnly();
        _measureTallyMeshReceiptsPlusDeltas();
    }

    function _measurePerRequestNaive() internal {
        PerRequestNaive c = new PerRequestNaive();
        vm.deal(payer, 10 ether);
        address payable r = payable(address(0xB1));
        vm.startPrank(payer);
        uint256 g0 = gasleft();
        c.pay{value: 0.01 ether}(r, keccak256("req"));
        uint256 gas = g0 - gasleft();
        vm.stopPrank();
        EvalCsv.appendRow(CSV, EvalCsv.csvRow3("PerRequestNaive", "pay", gas));
    }

    function _measurePerRequestEventOnly() internal {
        PerRequestEventOnly c = new PerRequestEventOnly();
        vm.deal(payer, 10 ether);
        address payable r = payable(address(0xB2));
        vm.startPrank(payer);
        uint256 g0 = gasleft();
        c.pay{value: 0.01 ether}(r, keccak256("req"));
        uint256 gas = g0 - gasleft();
        vm.stopPrank();
        EvalCsv.appendRow(CSV, EvalCsv.csvRow3("PerRequestEventOnly", "pay", gas));
    }

    function _measureSignedVoucherNetting() internal {
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
        uint256 gas = g0 - gasleft();
        EvalCsv.appendRow(CSV, EvalCsv.csvRow3("SignedVoucherNetting", "redeem", gas));
    }

    function _measureSignedVoucherAggregate() internal {
        SignedVoucherAggregate c = new SignedVoucherAggregate();
        address signer = vm.addr(payerKey);
        SignedVoucherAggregate.Voucher[] memory vs = new SignedVoucherAggregate.Voucher[](1);
        bytes[] memory sigs = new bytes[](1);
        vs[0] = SignedVoucherAggregate.Voucher({
            payer: signer,
            recipient: payable(address(0xB4)),
            sessionId: keccak256("s"),
            amount: 0.5 ether,
            nonce: 1,
            expiresAt: type(uint64).max
        });
        bytes32 digest = c.voucherDigest(vs[0]);
        (uint8 vSig, bytes32 r, bytes32 s) = vm.sign(payerKey, digest);
        sigs[0] = abi.encodePacked(r, s, vSig);
        vm.deal(address(c), 1 ether);
        uint256 g0 = gasleft();
        c.redeemBatch(vs, sigs);
        uint256 gas = g0 - gasleft();
        EvalCsv.appendRow(CSV, EvalCsv.csvRow3("SignedVoucherAggregate", "redeemBatch[N=1]", gas));
    }

    function _measureTallyMeshReceiptsOnly() internal {
        DepositEscrow escrow = new DepositEscrow();
        BatchSettlement bs = new BatchSettlement(address(escrow));
        bs.setAuthorizedSubmitter(submitter, true);
        bs.setChallengeWindow(900);
        vm.deal(submitter, 2 ether);
        vm.startPrank(submitter);
        bs.bond{value: 1 ether}();
        _setBlobHash(BLOB_HASH);
        uint256 g0 = gasleft();
        bs.submitOptimisticBatch(keccak256("b1"), keccak256("root"), bytes32(0), 1000, BLOB_HASH);
        uint256 gas = g0 - gasleft();
        vm.stopPrank();
        EvalCsv.appendRow(CSV, EvalCsv.csvRow3("TallyMeshOptReceiptsOnly", "submitOptimisticBatch", gas));
    }

    function _measureTallyMeshReceiptsPlusDeltas() internal {
        DepositEscrow escrow = new DepositEscrow();
        BatchSettlement bs = new BatchSettlement(address(escrow));
        bs.setAuthorizedSubmitter(submitter, true);
        bs.setChallengeWindow(900);
        vm.deal(submitter, 2 ether);
        vm.startPrank(submitter);
        bs.bond{value: 1 ether}();
        _setBlobHash(BLOB_HASH);
        uint256 g0 = gasleft();
        bs.submitOptimisticBatch(keccak256("b2"), keccak256("rRoot"), keccak256("dRoot"), 1000, BLOB_HASH);
        uint256 gas = g0 - gasleft();
        vm.stopPrank();
        EvalCsv.appendRow(CSV, EvalCsv.csvRow3("TallyMeshOptReceiptsPlusDeltas", "submitOptimisticBatch", gas));
    }

    receive() external payable {}

    function _setBlobHash(bytes32 blobHash) internal {
        bytes32[] memory blobHashes = new bytes32[](1);
        blobHashes[0] = blobHash;
        vm.blobhashes(blobHashes);
    }
}
