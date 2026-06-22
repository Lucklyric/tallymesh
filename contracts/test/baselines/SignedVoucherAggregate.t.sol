// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {SignedVoucherAggregate} from "../../src/baselines/SignedVoucherAggregate.sol";

contract SignedVoucherAggregateTest is Test {
    SignedVoucherAggregate baseline;
    uint256 payer1Key = 0xA1;
    uint256 payer2Key = 0xA2;
    address payer1;
    address payer2;
    address payable recipient = payable(address(0xB4));

    function setUp() public {
        baseline = new SignedVoucherAggregate();
        payer1 = vm.addr(payer1Key);
        payer2 = vm.addr(payer2Key);
    }

    function _voucher(address p, uint256 amount, uint256 nonce, bytes32 sid) internal view returns (SignedVoucherAggregate.Voucher memory) {
        return SignedVoucherAggregate.Voucher({
            payer: p,
            recipient: recipient,
            sessionId: sid,
            amount: amount,
            nonce: nonce,
            expiresAt: type(uint64).max
        });
    }

    function _sign(SignedVoucherAggregate.Voucher memory v, uint256 key) internal view returns (bytes memory) {
        bytes32 digest = baseline.voucherDigest(v);
        (uint8 vSig, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, vSig);
    }

    function test_redeemBatch_aggregatesNVouchers() public {
        SignedVoucherAggregate.Voucher[] memory vs = new SignedVoucherAggregate.Voucher[](2);
        bytes[] memory sigs = new bytes[](2);
        vs[0] = _voucher(payer1, 0.1 ether, 1, keccak256("s1"));
        sigs[0] = _sign(vs[0], payer1Key);
        vs[1] = _voucher(payer2, 0.2 ether, 1, keccak256("s2"));
        sigs[1] = _sign(vs[1], payer2Key);
        vm.deal(address(baseline), 1 ether);
        vm.prank(recipient);
        baseline.redeemBatch(vs, sigs);
        assertEq(recipient.balance, 0.3 ether);
        assertTrue(baseline.consumed(payer1, 1));
        assertTrue(baseline.consumed(payer2, 1));
    }

    function test_redeemBatch_revertsIfAnyVoucherInvalid() public {
        SignedVoucherAggregate.Voucher[] memory vs = new SignedVoucherAggregate.Voucher[](2);
        bytes[] memory sigs = new bytes[](2);
        vs[0] = _voucher(payer1, 0.1 ether, 1, keccak256("s1"));
        sigs[0] = _sign(vs[0], payer1Key);
        vs[1] = _voucher(payer2, 0.2 ether, 1, keccak256("s2"));
        sigs[1] = _sign(vs[1], payer1Key); // wrong key
        vm.deal(address(baseline), 1 ether);
        vm.prank(recipient);
        vm.expectRevert(SignedVoucherAggregate.InvalidSignature.selector);
        baseline.redeemBatch(vs, sigs);
        // Atomic: no state change.
        assertFalse(baseline.consumed(payer1, 1));
    }

    function test_redeemBatch_revertsOnLengthMismatch() public {
        SignedVoucherAggregate.Voucher[] memory vs = new SignedVoucherAggregate.Voucher[](2);
        bytes[] memory sigs = new bytes[](1);
        vs[0] = _voucher(payer1, 0.1 ether, 1, keccak256("s1"));
        vs[1] = _voucher(payer2, 0.2 ether, 1, keccak256("s2"));
        sigs[0] = _sign(vs[0], payer1Key);
        vm.expectRevert(SignedVoucherAggregate.LengthMismatch.selector);
        baseline.redeemBatch(vs, sigs);
    }

    /// @notice Apples-to-apples gas sweep for the SVA aggregate-voucher baseline.
    /// Same N grid as the TallyMesh sweep so per-leaf gas can be compared head-to-head.
    function test_gas_sweep_sva_aggregate() public {
        uint256[5] memory NS = [uint256(1), uint256(4), uint256(16), uint256(64), uint256(256)];
        for (uint256 k = 0; k < NS.length; k++) {
            _measureOneN_sva(NS[k]);
        }
    }

    function _signFresh(SignedVoucherAggregate.Voucher memory v, uint256 key, SignedVoucherAggregate target)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = target.voucherDigest(v);
        (uint8 vSig, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, vSig);
    }

    function _measureOneN_sva(uint256 n) internal {
        SignedVoucherAggregate fresh = new SignedVoucherAggregate();
        uint256 amt = 0.0001 ether;
        bytes32 sid = keccak256(abi.encode("sweep", n));
        SignedVoucherAggregate.Voucher[] memory vs = new SignedVoucherAggregate.Voucher[](n);
        bytes[] memory sigs = new bytes[](n);
        for (uint256 i = 0; i < n; i++) {
            vs[i] = SignedVoucherAggregate.Voucher({
                payer: payer1,
                recipient: recipient,
                sessionId: sid,
                amount: amt,
                nonce: i + 1,
                expiresAt: type(uint64).max
            });
            sigs[i] = _signFresh(vs[i], payer1Key, fresh);
        }
        vm.deal(address(fresh), n * amt + 1 ether);
        vm.prank(recipient);
        uint256 g0 = gasleft();
        fresh.redeemBatch(vs, sigs);
        uint256 used = g0 - gasleft();
        console2.log("SVA_REDEEM_GAS_N", n, "gas", used);
        console2.log("                   per-leaf", used / n);
    }
}
