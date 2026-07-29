// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";

contract DepositEscrowHandler is Test {
    DepositEscrow public immutable escrow;
    address public immutable payer;
    address public immutable settler;
    bytes32 public constant SESSION = bytes32("inv-sess");

    uint256 public ghostDeposited;
    uint256 public ghostWithdrawn;

    constructor(DepositEscrow escrow_, address payer_, address settler_) {
        escrow = escrow_;
        payer = payer_;
        settler = settler_;
    }

    function deposit(uint96 amount) external {
        amount = uint96(bound(amount, 0, 10 ether));
        vm.deal(payer, payer.balance + amount);
        vm.prank(payer);
        escrow.deposit{value: amount}();
        ghostDeposited += amount;
    }

    function withdraw(uint96 amount) external {
        uint256 free = escrow.balanceOf(payer);
        amount = uint96(bound(amount, 0, free));
        vm.prank(payer);
        escrow.withdraw(amount, payable(payer));
        ghostWithdrawn += amount;
    }

    function reserve(uint96 amount) external {
        uint256 free = escrow.balanceOf(payer);
        amount = uint96(bound(amount, 0, free));
        vm.prank(settler);
        escrow.reserve(SESSION, payer, amount);
    }

    function release(uint96 amount) external {
        uint256 reserved = escrow.reservedOf(SESSION, payer);
        amount = uint96(bound(amount, 0, reserved));
        vm.prank(settler);
        escrow.release(SESSION, payer, amount);
    }
}
