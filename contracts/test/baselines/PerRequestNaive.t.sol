// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PerRequestNaive} from "../../src/baselines/PerRequestNaive.sol";

contract PerRequestNaiveTest is Test {
    PerRequestNaive baseline;
    address payer = address(0xA1);
    address payable recipient = payable(address(0xB1));

    function setUp() public {
        baseline = new PerRequestNaive();
        vm.deal(payer, 100 ether);
    }

    function test_pay_transfersAndIncrementsTotal() public {
        vm.prank(payer);
        baseline.pay{value: 0.01 ether}(recipient, keccak256("req-1"));
        assertEq(recipient.balance, 0.01 ether);
        assertEq(baseline.totalPaid(payer, recipient), 0.01 ether);
    }

    function test_pay_emitsRequestSettled() public {
        vm.expectEmit(true, true, true, true, address(baseline));
        emit PerRequestNaive.RequestSettled(payer, recipient, 0.01 ether, keccak256("req-1"));
        vm.prank(payer);
        baseline.pay{value: 0.01 ether}(recipient, keccak256("req-1"));
    }

    function test_pay_revertsOnZeroAmount() public {
        vm.prank(payer);
        vm.expectRevert(PerRequestNaive.InvalidAmount.selector);
        baseline.pay{value: 0}(recipient, keccak256("req-1"));
    }

    function test_pay_revertsOnZeroRecipient() public {
        vm.prank(payer);
        vm.expectRevert(PerRequestNaive.InvalidRecipient.selector);
        baseline.pay{value: 0.01 ether}(payable(address(0)), keccak256("req-1"));
    }
}
