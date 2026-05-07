// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";

contract LegacyReserveDisabledByDefaultTest is Test {
    DepositEscrow escrow;
    BatchSettlement settlement;

    address constant OWNER = address(0xDEEDA);
    address constant PAYER = address(0xA11CE);
    address payable constant SERVICE = payable(address(0x5E2C1));
    bytes32 constant SESSION = bytes32("legacy-disabled");

    function setUp() public {
        vm.prank(OWNER);
        escrow = new DepositEscrow();
        vm.prank(OWNER);
        settlement = new BatchSettlement(address(escrow));
        vm.prank(OWNER);
        escrow.setAuthorizedSettler(address(settlement), true);

        vm.deal(PAYER, 10 ether);
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();
    }

    function test_legacyReserveSession_disabledByDefaultAndOwnerToggleEnables() public {
        assertFalse(settlement.legacyReserveEnabled());

        vm.prank(PAYER);
        vm.expectRevert(BatchSettlement.LegacyReserveDisabled.selector);
        settlement.reserveSession(SESSION, SERVICE, 0.5 ether);

        vm.prank(OWNER);
        settlement.setLegacyReserveEnabled(true);

        vm.prank(PAYER);
        settlement.reserveSession(SESSION, SERVICE, 0.5 ether);

        (address payer, address recipient, uint256 amount, bool open) = settlement.sessions(SESSION);
        assertEq(payer, PAYER);
        assertEq(recipient, SERVICE);
        assertEq(amount, 0.5 ether);
        assertTrue(open);
    }
}
