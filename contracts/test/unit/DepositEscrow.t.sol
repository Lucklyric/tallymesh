// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";

contract DepositEscrowTest is Test {
    DepositEscrow escrow;
    address constant OWNER = address(0xDEEDA);
    address constant SETTLER = address(0x5E771E);
    address constant SETTLER2 = address(0x5E772E);
    address payable PAYER = payable(address(0xA11CE));
    bytes32 constant SESSION = bytes32("sess-1");

    function setUp() public {
        vm.prank(OWNER);
        escrow = new DepositEscrow();
        vm.prank(OWNER);
        escrow.setAuthorizedSettler(SETTLER, true);
        vm.deal(PAYER, 10 ether);
    }

    function test_setAuthorizedSettler_onlyOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(DepositEscrow.NotOwner.selector);
        escrow.setAuthorizedSettler(SETTLER2, true);
    }

    function test_setAuthorizedSettler_grantAndRevoke() public {
        vm.prank(OWNER);
        escrow.setAuthorizedSettler(SETTLER2, true);
        assertTrue(escrow.authorizedSettlers(SETTLER2));
        vm.prank(OWNER);
        escrow.setAuthorizedSettler(SETTLER2, false);
        assertFalse(escrow.authorizedSettlers(SETTLER2));
    }

    function test_deposit_increasesBalance() public {
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        assertEq(escrow.balanceOf(PAYER), 1 ether);
    }

    function test_withdraw_decreasesBalance() public {
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        vm.prank(PAYER);
        escrow.withdraw(0.4 ether, PAYER);
        assertEq(escrow.balanceOf(PAYER), 0.6 ether);
        assertEq(PAYER.balance, 9.4 ether);
    }

    function test_withdraw_revertsOnInsufficientFreeBalance() public {
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        vm.prank(SETTLER);
        escrow.reserve(SESSION, PAYER, 0.7 ether);
        vm.prank(PAYER);
        vm.expectRevert(DepositEscrow.InsufficientFreeBalance.selector);
        escrow.withdraw(0.4 ether, PAYER);
    }

    function test_reserve_onlyAuthorizedSettler() public {
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        vm.prank(PAYER);
        vm.expectRevert(DepositEscrow.NotAuthorizedSettler.selector);
        escrow.reserve(SESSION, PAYER, 0.5 ether);
    }

    function test_reserve_revertsForUnauthorizedSettler() public {
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        vm.prank(SETTLER2); // not authorized
        vm.expectRevert(DepositEscrow.NotAuthorizedSettler.selector);
        escrow.reserve(SESSION, PAYER, 0.5 ether);
    }

    function test_reserve_movesBalanceToReserved() public {
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        vm.prank(SETTLER);
        escrow.reserve(SESSION, PAYER, 0.5 ether);
        assertEq(escrow.balanceOf(PAYER), 0.5 ether);
        assertEq(escrow.reservedOf(SESSION, PAYER), 0.5 ether);
    }

    function test_release_returnsFundsToFreeBalance() public {
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        vm.prank(SETTLER);
        escrow.reserve(SESSION, PAYER, 0.5 ether);
        vm.prank(SETTLER);
        escrow.release(SESSION, PAYER, 0.3 ether);
        assertEq(escrow.balanceOf(PAYER), 0.8 ether);
        assertEq(escrow.reservedOf(SESSION, PAYER), 0.2 ether);
    }

    function test_release_revertsOnOverRelease() public {
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        vm.prank(SETTLER);
        escrow.reserve(SESSION, PAYER, 0.5 ether);
        vm.prank(SETTLER);
        vm.expectRevert(DepositEscrow.InsufficientReserved.selector);
        escrow.release(SESSION, PAYER, 0.6 ether);
    }

    function test_reserve_revertsOnInsufficientFreeBalance() public {
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        vm.prank(SETTLER);
        vm.expectRevert(DepositEscrow.InsufficientFreeBalance.selector);
        escrow.reserve(SESSION, PAYER, 1.1 ether);
    }

    /// @dev Race scenario: reserve then attempt to withdraw the reserved slice.
    /// Defends attack 15 in §2.3 (escrow withdraw / reservation race).
    function test_withdrawAfterReserve_cannotDoubleSpend() public {
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
        vm.prank(SETTLER);
        escrow.reserve(SESSION, PAYER, 0.5 ether);
        vm.prank(PAYER);
        vm.expectRevert(DepositEscrow.InsufficientFreeBalance.selector);
        escrow.withdraw(0.6 ether, PAYER);
        vm.prank(PAYER);
        escrow.withdraw(0.5 ether, PAYER);
        assertEq(escrow.balanceOf(PAYER), 0);
        assertEq(escrow.reservedOf(SESSION, PAYER), 0.5 ether);
    }
}
