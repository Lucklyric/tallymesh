// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";
import {DepositEscrowHandler} from "./DepositEscrowHandler.sol";

contract DepositEscrowInvariantTest is Test {
    DepositEscrow escrow;
    DepositEscrowHandler handler;
    address constant OWNER = address(0xDEEDA);
    address constant PAYER = address(0xA11CE);
    address constant SETTLER = address(0x5E771E);

    function setUp() public {
        vm.prank(OWNER);
        escrow = new DepositEscrow();
        vm.prank(OWNER);
        escrow.setAuthorizedSettler(SETTLER, true);
        handler = new DepositEscrowHandler(escrow, PAYER, SETTLER);
        targetContract(address(handler));
    }

    /// @dev Total accounted-for value = free + reserved must never exceed
    /// (deposited - withdrawn). The escrow cannot conjure ETH.
    function invariant_balancesNeverExceedNetDeposits() public view {
        uint256 free = escrow.balanceOf(PAYER);
        uint256 reserved = escrow.reservedOf(handler.SESSION(), PAYER);
        uint256 net = handler.ghostDeposited() - handler.ghostWithdrawn();
        assertLe(free + reserved, net, "invariant: accounted balance exceeds net deposits");
    }

    /// @dev Contract ETH balance equals free + reserved (no leakage).
    function invariant_contractEthEqualsAccounted() public view {
        uint256 free = escrow.balanceOf(PAYER);
        uint256 reserved = escrow.reservedOf(handler.SESSION(), PAYER);
        assertEq(address(escrow).balance, free + reserved, "invariant: ETH escapes accounting");
    }
}
