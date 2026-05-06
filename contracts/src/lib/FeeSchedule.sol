// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Hash-locked fee-schedule commitment.
library FeeSchedule {
    bytes32 internal constant SCHEDULE_TYPEHASH = keccak256(
        "FeeSchedule(address paymentToken,uint256 unitPrice,uint256 maxPerCall,bytes32 currency)"
    );

    struct Schedule {
        address paymentToken;
        uint256 unitPrice;
        uint256 maxPerCall;
        bytes32 currency;
    }

    function commit(Schedule memory s) internal pure returns (bytes32) {
        return keccak256(abi.encode(SCHEDULE_TYPEHASH, s.paymentToken, s.unitPrice, s.maxPerCall, s.currency));
    }

    function verify(bytes32 commitment, Schedule memory s) internal pure returns (bool) {
        return commit(s) == commitment;
    }
}
