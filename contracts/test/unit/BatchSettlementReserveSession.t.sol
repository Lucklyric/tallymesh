// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";

contract BatchSettlementReserveSessionTest is Test {
    DepositEscrow escrow;
    BatchSettlement settlement;
    address constant OWNER = address(0xDEEDA);
    address constant PAYER = address(0xA11CE);
    address payable constant SERVICE = payable(address(0x5E2C1));
    bytes32 constant SESSION = bytes32("sess-1");

    function setUp() public {
        vm.prank(OWNER);
        escrow = new DepositEscrow();
        vm.prank(OWNER);
        settlement = new BatchSettlement(address(escrow));
        vm.prank(OWNER);
        escrow.setAuthorizedSettler(address(settlement), true);
        vm.deal(PAYER, 10 ether);
        vm.prank(PAYER);
        escrow.deposit{value: 2 ether}();
    }

    function test_reserveSession_recordsMetadataAndCallsEscrow() public {
        vm.prank(PAYER);
        settlement.reserveSession(SESSION, SERVICE, 0.5 ether);
        (address payer, address recipient, uint256 amount, bool open) = settlement.sessions(SESSION);
        assertEq(payer, PAYER);
        assertEq(recipient, SERVICE);
        assertEq(amount, 0.5 ether);
        assertTrue(open);
        assertEq(escrow.reservedOf(SESSION, PAYER), 0.5 ether);
    }

    function test_reserveSession_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit BatchSettlement.SessionReserved(SESSION, PAYER, SERVICE, 0.5 ether);
        vm.prank(PAYER);
        settlement.reserveSession(SESSION, SERVICE, 0.5 ether);
    }

    function test_reserveSession_rejectsDuplicate() public {
        vm.prank(PAYER);
        settlement.reserveSession(SESSION, SERVICE, 0.5 ether);
        vm.prank(PAYER);
        vm.expectRevert(BatchSettlement.SessionAlreadyOpen.selector);
        settlement.reserveSession(SESSION, SERVICE, 0.1 ether);
    }

    function test_reserveSession_revertsOnZeroRecipient() public {
        vm.prank(PAYER);
        vm.expectRevert(BatchSettlement.InvalidRecipient.selector);
        settlement.reserveSession(SESSION, payable(address(0)), 0.5 ether);
    }

    function test_reserveSession_revertsOnZeroAmount() public {
        vm.prank(PAYER);
        vm.expectRevert(BatchSettlement.InvalidAmount.selector);
        settlement.reserveSession(SESSION, SERVICE, 0);
    }

    function test_reserveSession_propagatesEscrowFailure() public {
        vm.prank(PAYER);
        vm.expectRevert(DepositEscrow.InsufficientFreeBalance.selector);
        settlement.reserveSession(SESSION, SERVICE, 5 ether);
    }
}
