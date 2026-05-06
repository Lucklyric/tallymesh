// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Straw-man baseline B1a. Each request settles on-chain via direct
/// ETH transfer plus a storage write tracking cumulative paid per
/// (payer, recipient). One on-chain tx per request, worst-case gas/call.
contract PerRequestNaive {
    error InvalidAmount();
    error InvalidRecipient();
    error TransferFailed();

    mapping(address => mapping(address => uint256)) public totalPaid;

    event RequestSettled(address indexed payer, address indexed recipient, uint256 amount, bytes32 requestHash);

    function pay(address payable recipient, bytes32 requestHash) external payable {
        if (msg.value == 0) revert InvalidAmount();
        if (recipient == address(0)) revert InvalidRecipient();
        totalPaid[msg.sender][recipient] += msg.value;
        (bool ok,) = recipient.call{value: msg.value}("");
        if (!ok) revert TransferFailed();
        emit RequestSettled(msg.sender, recipient, msg.value, requestHash);
    }
}
