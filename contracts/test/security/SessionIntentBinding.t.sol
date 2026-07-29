// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {BatchSettlement} from "../../src/BatchSettlement.sol";
import {DepositEscrow} from "../../src/DepositEscrow.sol";
import {EIP712Domain} from "../../src/lib/EIP712Domain.sol";

contract SessionIntentBindingTest is Test {
    DepositEscrow escrow;
    BatchSettlement settlement;

    uint256 constant PAYER_PK = 0xA11CE;
    uint256 constant ATTACKER_PK = 0xB0B;
    address PAYER;
    address payable constant SERVICE = payable(address(0x5E2C1));
    bytes32 constant SESSION = bytes32("sess-intent");
    bytes32 constant SESSION_INTENT_TYPEHASH = keccak256(
        "SessionIntent(bytes32 sessionId,address payer,address recipient,uint256 amount,uint256 maxAmount,uint64 expiry)"
    );

    function setUp() public {
        PAYER = vm.addr(PAYER_PK);
        escrow = new DepositEscrow();
        settlement = new BatchSettlement(address(escrow));
        escrow.setAuthorizedSettler(address(settlement), true);
        vm.deal(PAYER, 10 ether);
        vm.prank(PAYER);
        escrow.deposit{value: 2 ether}();
    }

    function test_reserveSessionWithIntent_revertsOnBadSig() public {
        BatchSettlement.SessionIntent memory intent = _intent(0.5 ether, 0.5 ether, uint64(block.timestamp + 1 days));
        bytes memory sig = _sign(intent, ATTACKER_PK);

        vm.expectRevert(BatchSettlement.InvalidSessionIntentSignature.selector);
        settlement.reserveSessionWithIntent(intent, sig);
    }

    function test_reserveSessionWithIntent_revertsOnExpiredIntent() public {
        vm.warp(2 days);
        BatchSettlement.SessionIntent memory intent = _intent(0.5 ether, 0.5 ether, uint64(block.timestamp - 1));
        bytes memory sig = _sign(intent, PAYER_PK);

        vm.expectRevert(BatchSettlement.SessionIntentExpired.selector);
        settlement.reserveSessionWithIntent(intent, sig);
    }

    function test_reserveSessionWithIntent_revertsWhenAmountExceedsMaxAmount() public {
        BatchSettlement.SessionIntent memory intent = _intent(0.6 ether, 0.5 ether, uint64(block.timestamp + 1 days));
        bytes memory sig = _sign(intent, PAYER_PK);

        vm.expectRevert(BatchSettlement.SessionIntentOverBudget.selector);
        settlement.reserveSessionWithIntent(intent, sig);
    }

    function test_reserveSessionWithIntent_reservesForSignedPayer() public {
        BatchSettlement.SessionIntent memory intent = _intent(0.5 ether, 0.5 ether, uint64(block.timestamp + 1 days));
        bytes memory sig = _sign(intent, PAYER_PK);
        address relayer = address(0x1234);

        vm.prank(relayer);
        settlement.reserveSessionWithIntent(intent, sig);

        (address payer, address recipient, uint256 amount, bool open) = settlement.sessions(SESSION);
        assertEq(payer, PAYER);
        assertEq(recipient, SERVICE);
        assertEq(amount, 0.5 ether);
        assertTrue(open);
        assertEq(escrow.reservedOf(SESSION, PAYER), 0.5 ether);
    }

    function _intent(uint256 amount, uint256 maxAmount, uint64 expiry)
        internal
        view
        returns (BatchSettlement.SessionIntent memory)
    {
        return BatchSettlement.SessionIntent({
            sessionId: SESSION,
            payer: PAYER,
            recipient: SERVICE,
            amount: amount,
            maxAmount: maxAmount,
            expiry: expiry
        });
    }

    function _sign(BatchSettlement.SessionIntent memory intent, uint256 pk) internal view returns (bytes memory) {
        bytes32 digest = _digest(intent);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _digest(BatchSettlement.SessionIntent memory intent) internal view returns (bytes32) {
        bytes32 domain = EIP712Domain.domainSeparator("TallyMesh", "1", block.chainid, address(settlement));
        bytes32 structHash = keccak256(
            abi.encode(
                SESSION_INTENT_TYPEHASH,
                intent.sessionId,
                intent.payer,
                intent.recipient,
                intent.amount,
                intent.maxAmount,
                intent.expiry
            )
        );
        return EIP712Domain.hashTypedData(domain, structHash);
    }
}
