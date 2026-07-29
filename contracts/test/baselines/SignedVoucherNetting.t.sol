// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SignedVoucherNetting} from "../../src/baselines/SignedVoucherNetting.sol";

contract SignedVoucherNettingTest is Test {
    SignedVoucherNetting baseline;
    uint256 payerKey = 0xA0A0;
    address payer;
    address payable recipient = payable(address(0xB3));

    function setUp() public {
        baseline = new SignedVoucherNetting();
        payer = vm.addr(payerKey);
        vm.deal(payer, 100 ether);
    }

    function _signVoucher(SignedVoucherNetting.Voucher memory v) internal view returns (bytes memory) {
        bytes32 digest = baseline.voucherDigest(v);
        (uint8 vSig, bytes32 r, bytes32 s) = vm.sign(payerKey, digest);
        return abi.encodePacked(r, s, vSig);
    }

    function test_redeem_transfersFullAmountAndConsumesNonce() public {
        SignedVoucherNetting.Voucher memory v = SignedVoucherNetting.Voucher({
            payer: payer,
            recipient: recipient,
            sessionId: keccak256("session-1"),
            amount: 0.5 ether,
            nonce: 1,
            expiresAt: type(uint64).max
        });
        bytes memory sig = _signVoucher(v);
        vm.deal(address(baseline), 0.5 ether); // pre-fund
        vm.prank(recipient);
        baseline.redeem(v, sig);
        assertEq(recipient.balance, 0.5 ether);
        assertTrue(baseline.consumed(payer, v.nonce));
    }

    function test_redeem_revertsOnReplay() public {
        SignedVoucherNetting.Voucher memory v = SignedVoucherNetting.Voucher({
            payer: payer,
            recipient: recipient,
            sessionId: keccak256("session-1"),
            amount: 0.5 ether,
            nonce: 1,
            expiresAt: type(uint64).max
        });
        bytes memory sig = _signVoucher(v);
        vm.deal(address(baseline), 1 ether);
        vm.prank(recipient);
        baseline.redeem(v, sig);
        vm.expectRevert(SignedVoucherNetting.AlreadyConsumed.selector);
        vm.prank(recipient);
        baseline.redeem(v, sig);
    }

    function test_redeem_revertsOnExpired() public {
        SignedVoucherNetting.Voucher memory v = SignedVoucherNetting.Voucher({
            payer: payer,
            recipient: recipient,
            sessionId: keccak256("session-1"),
            amount: 0.5 ether,
            nonce: 1,
            expiresAt: 100
        });
        vm.warp(200);
        bytes memory sig = _signVoucher(v);
        vm.deal(address(baseline), 1 ether);
        vm.prank(recipient);
        vm.expectRevert(SignedVoucherNetting.VoucherExpired.selector);
        baseline.redeem(v, sig);
    }

    function test_redeem_revertsOnBadSignature() public {
        SignedVoucherNetting.Voucher memory v = SignedVoucherNetting.Voucher({
            payer: payer,
            recipient: recipient,
            sessionId: keccak256("session-1"),
            amount: 0.5 ether,
            nonce: 1,
            expiresAt: type(uint64).max
        });
        // Sign with a different key.
        (uint8 vSig, bytes32 r, bytes32 s) = vm.sign(0xBEEF, baseline.voucherDigest(v));
        bytes memory badSig = abi.encodePacked(r, s, vSig);
        vm.deal(address(baseline), 1 ether);
        vm.prank(recipient);
        vm.expectRevert(SignedVoucherNetting.InvalidSignature.selector);
        baseline.redeem(v, badSig);
    }
}
