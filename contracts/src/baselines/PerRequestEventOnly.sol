// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Storage-minimized naive baseline B1b. Each request emits an event
/// and forwards ETH; no on-chain storage of cumulative state. Receipts live
/// in the event log. Tighter naive baseline for the headline plot.
contract PerRequestEventOnly {
    error InvalidAmount();
    error InvalidRecipient();
    error TransferFailed();

    event RequestSettled(address indexed payer, address indexed recipient, uint256 amount, bytes32 requestHash);

    function pay(address payable recipient, bytes32 requestHash) external payable {
        if (msg.value == 0) revert InvalidAmount();
        if (recipient == address(0)) revert InvalidRecipient();
        (bool ok,) = recipient.call{value: msg.value}("");
        if (!ok) revert TransferFailed();
        emit RequestSettled(msg.sender, recipient, msg.value, requestHash);
    }
}
