// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ServiceRegistry} from "../../src/ServiceRegistry.sol";
import {RolePolicyRegistry} from "../../src/RolePolicyRegistry.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";
import {DisputeManager} from "../../src/DisputeManager.sol";
import {ReceiptLib} from "../../src/lib/ReceiptLib.sol";

contract EndToEndTest is Test {
    ServiceRegistry serviceRegistry;
    RolePolicyRegistry policyRegistry;
    DepositEscrow escrow;
    BatchSettlement settlement;
    DisputeManager dispute;

    address constant OWNER = address(0xDEEDA);
    address constant SERVICE_OWNER = address(0xA11CE);
    address constant SUBMITTER = address(0x5BB1);
    address constant PAYER = address(0xCAFE);
    address payable constant SERVICE = payable(address(0x5E2C1));
    bytes32 constant SERVICE_ID = bytes32("svc-1");
    bytes32 constant SESSION = bytes32("sess-1");
    bytes32 constant BATCH_ID = bytes32("batch-1");
    uint256 constant CHALLENGE_WINDOW = 900;
    uint256 constant CHARGED_CEILING = 1 ether;

    function test_fullFlow_depositToBatchToServicePayout() public {
        vm.prank(OWNER);
        serviceRegistry = new ServiceRegistry();
        policyRegistry = new RolePolicyRegistry(address(serviceRegistry));
        vm.prank(OWNER);
        escrow = new DepositEscrow();
        vm.prank(OWNER);
        settlement = new BatchSettlement(address(escrow));
        vm.prank(OWNER);
        dispute = new DisputeManager(address(settlement));

        vm.prank(OWNER);
        settlement.setChallengeWindow(uint64(CHALLENGE_WINDOW));
        vm.prank(OWNER);
        settlement.setChargedCeiling(CHARGED_CEILING);
        vm.prank(OWNER);
        settlement.setAuthorizedSubmitter(SUBMITTER, true);
        vm.prank(OWNER);
        settlement.setDisputeManager(address(dispute));
        vm.prank(OWNER);
        settlement.setLegacyReserveEnabled(true);
        vm.prank(OWNER);
        escrow.setAuthorizedSettler(address(settlement), true);

        vm.prank(SERVICE_OWNER);
        serviceRegistry.registerService(SERVICE_ID, keccak256("meta"), keccak256("fee"));

        vm.deal(SUBMITTER, 10 ether);
        vm.prank(SUBMITTER);
        settlement.bond{value: 2 ether}();

        vm.deal(PAYER, 10 ether);
        vm.prank(PAYER);
        escrow.deposit{value: 1 ether}();

        vm.prank(PAYER);
        settlement.reserveSession(SESSION, SERVICE, 0.5 ether);

        ReceiptLib.Receipt memory r = ReceiptLib.Receipt({
            sessionId: SESSION,
            seq: 1,
            requestHash: keccak256("req"),
            resultHash: keccak256("res"),
            chargedAmount: 0.3 ether,
            statusCode: bytes32("OK"),
            serviceTimestamp: uint64(block.timestamp)
        });
        bytes32 root = ReceiptLib.leafHash(r);
        vm.prank(SUBMITTER);
        settlement.submitOptimisticBatch(BATCH_ID, root, bytes32(0), 1);

        vm.warp(block.timestamp + CHALLENGE_WINDOW + 1);
        settlement.finalizeBatch(BATCH_ID);

        bytes32[] memory proof = new bytes32[](0);
        settlement.claimPayout(BATCH_ID, r, proof);

        assertEq(SERVICE.balance, 0.3 ether);
        assertEq(escrow.balanceOf(PAYER), 0.5 ether);
        assertEq(escrow.reservedOf(SESSION, PAYER), 0.2 ether);
        assertEq(settlement.bondOf(SUBMITTER), 2 ether);
        assertEq(settlement.pendingBatchesOf(SUBMITTER), 0);
    }
}
