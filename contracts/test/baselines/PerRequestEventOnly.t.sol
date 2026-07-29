// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PerRequestEventOnly} from "../../src/baselines/PerRequestEventOnly.sol";

contract PerRequestEventOnlyTest is Test {
    PerRequestEventOnly baseline;
    address payer = address(0xA2);
    address payable recipient = payable(address(0xB2));

    function setUp() public {
        baseline = new PerRequestEventOnly();
        vm.deal(payer, 100 ether);
    }

    function test_pay_transfersAndEmits() public {
        vm.expectEmit(true, true, true, true, address(baseline));
        emit PerRequestEventOnly.RequestSettled(payer, recipient, 0.01 ether, keccak256("req-1"));
        vm.prank(payer);
        baseline.pay{value: 0.01 ether}(recipient, keccak256("req-1"));
        assertEq(recipient.balance, 0.01 ether);
    }

    function test_pay_writesNoStorage() public {
        // No public state to read — confirm absence by reading slot 0 directly.
        bytes32 before_ = vm.load(address(baseline), bytes32(uint256(0)));
        vm.prank(payer);
        baseline.pay{value: 0.01 ether}(recipient, keccak256("req-1"));
        bytes32 after_ = vm.load(address(baseline), bytes32(uint256(0)));
        assertEq(before_, after_, "no storage writes on happy path");
    }

    function test_pay_revertsOnZeroAmount() public {
        vm.prank(payer);
        vm.expectRevert(PerRequestEventOnly.InvalidAmount.selector);
        baseline.pay{value: 0}(recipient, keccak256("req-1"));
    }
}
