// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";

contract BatchSettlementBondsTest is Test {
    BatchSettlement settlement;
    address constant OWNER = address(0xDEEDA);
    address constant SUBMITTER1 = address(0x5BB1);
    address constant SUBMITTER2 = address(0x5BB2);

    function setUp() public {
        vm.prank(OWNER);
        settlement = new BatchSettlement(address(0xE5C20E));
        vm.deal(SUBMITTER1, 10 ether);
        vm.deal(SUBMITTER2, 10 ether);
    }

    function test_bond_increasesBondAndTotalStake() public {
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER1, true);
        vm.prank(SUBMITTER1);
        settlement.bond{value: 2 ether}();
        assertEq(settlement.bondOf(SUBMITTER1), 2 ether);
        assertEq(settlement.totalBondedStake(), 2 ether);
    }

    function test_bond_revertsForUnauthorizedSubmitter() public {
        vm.prank(SUBMITTER1);
        vm.expectRevert(BatchSettlement.NotAuthorizedSubmitter.selector);
        settlement.bond{value: 1 ether}();
    }

    function test_unbond_decreasesBondAndTotalStake() public {
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER1, true);
        vm.prank(SUBMITTER1);
        settlement.bond{value: 2 ether}();
        vm.prank(SUBMITTER1);
        settlement.unbond(0.5 ether);
        assertEq(settlement.bondOf(SUBMITTER1), 1.5 ether);
        assertEq(settlement.totalBondedStake(), 1.5 ether);
        assertEq(SUBMITTER1.balance, 8.5 ether);
    }

    function test_unbond_revertsOnInsufficientBond() public {
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER1, true);
        vm.prank(SUBMITTER1);
        settlement.bond{value: 1 ether}();
        vm.prank(SUBMITTER1);
        vm.expectRevert(BatchSettlement.InsufficientBond.selector);
        settlement.unbond(2 ether);
    }

    function test_setAuthorizedSubmitter_onlyOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(BatchSettlement.NotOwner.selector);
        settlement.setAuthorizedSubmitter(SUBMITTER1, true);
    }

    function test_setAuthorizedSubmitter_grantAndRevoke() public {
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER1, true);
        assertTrue(settlement.authorizedSubmitters(SUBMITTER1));
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER1, false);
        assertFalse(settlement.authorizedSubmitters(SUBMITTER1));
    }

    function test_totalBondedStake_aggregatesAcrossSubmitters() public {
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER1, true);
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER2, true);
        vm.prank(SUBMITTER1);
        settlement.bond{value: 2 ether}();
        vm.prank(SUBMITTER2);
        settlement.bond{value: 3 ether}();
        assertEq(settlement.totalBondedStake(), 5 ether);
    }

    function test_bond_emitsEvent() public {
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER1, true);
        vm.expectEmit(true, false, false, true);
        emit BatchSettlement.SubmitterBonded(SUBMITTER1, 1 ether);
        vm.prank(SUBMITTER1);
        settlement.bond{value: 1 ether}();
    }

}
