// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {FeeSchedule} from "../../src/lib/FeeSchedule.sol";

contract FeeScheduleTest is Test {
    function test_typeHash_matchesCanonicalString() public pure {
        bytes32 expected =
            keccak256("FeeSchedule(address paymentToken,uint256 unitPrice,uint256 maxPerCall,bytes32 currency)");
        assertEq(FeeSchedule.SCHEDULE_TYPEHASH, expected, "SCHEDULE_TYPEHASH drift");
    }

    function test_commit_isStableForSameInputs() public pure {
        FeeSchedule.Schedule memory s = FeeSchedule.Schedule({
            paymentToken: address(0xCAFE),
            unitPrice: 1000,
            maxPerCall: 5000,
            currency: bytes32("USDC")
        });
        bytes32 a = FeeSchedule.commit(s);
        bytes32 b = FeeSchedule.commit(s);
        assertEq(a, b);
    }

    /// @dev Solidity memory-to-memory struct assignment is by reference (the
    /// language spec). Use two independent struct literals instead of copy-and-mutate.
    function test_commit_changesWithUnitPrice() public pure {
        FeeSchedule.Schedule memory base = FeeSchedule.Schedule({
            paymentToken: address(0xCAFE),
            unitPrice: 1000,
            maxPerCall: 5000,
            currency: bytes32("USDC")
        });
        FeeSchedule.Schedule memory bumped = FeeSchedule.Schedule({
            paymentToken: address(0xCAFE),
            unitPrice: 1001,
            maxPerCall: 5000,
            currency: bytes32("USDC")
        });
        assertTrue(FeeSchedule.commit(base) != FeeSchedule.commit(bumped));
    }

    function test_verify_acceptsExactSchedule() public pure {
        FeeSchedule.Schedule memory s = FeeSchedule.Schedule({
            paymentToken: address(0xCAFE),
            unitPrice: 1000,
            maxPerCall: 5000,
            currency: bytes32("USDC")
        });
        bytes32 c = FeeSchedule.commit(s);
        assertTrue(FeeSchedule.verify(c, s));
    }

    function test_verify_rejectsTamperedSchedule() public pure {
        FeeSchedule.Schedule memory original = FeeSchedule.Schedule({
            paymentToken: address(0xCAFE),
            unitPrice: 1000,
            maxPerCall: 5000,
            currency: bytes32("USDC")
        });
        bytes32 c = FeeSchedule.commit(original);
        FeeSchedule.Schedule memory tampered = FeeSchedule.Schedule({
            paymentToken: address(0xCAFE),
            unitPrice: 999,
            maxPerCall: 5000,
            currency: bytes32("USDC")
        });
        assertFalse(FeeSchedule.verify(c, tampered));
    }
}
