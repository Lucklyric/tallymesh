// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Signatures} from "../lib/Signatures.sol";
import {EIP712Domain} from "../lib/EIP712Domain.sol";

/// @notice x402-style baseline B2a. Payer signs an off-chain voucher granting
/// the recipient a one-shot withdrawal up to a fixed amount. Per-request gas
/// amortizes across the single redemption tx; per-session settlement.
contract SignedVoucherNetting {
    error InvalidSignature();
    error AlreadyConsumed();
    error VoucherExpired();
    error InvalidAmount();
    error TransferFailed();

    bytes32 internal constant VOUCHER_TYPEHASH = keccak256(
        "Voucher(address payer,address recipient,bytes32 sessionId,uint256 amount,uint256 nonce,uint64 expiresAt)"
    );

    struct Voucher {
        address payer;
        address payable recipient;
        bytes32 sessionId;
        uint256 amount;
        uint256 nonce;
        uint64 expiresAt;
    }

    bytes32 public immutable DOMAIN_SEPARATOR;
    mapping(address => mapping(uint256 => bool)) public consumed;

    event VoucherRedeemed(
        address indexed payer,
        address indexed recipient,
        bytes32 indexed sessionId,
        uint256 amount,
        uint256 nonce
    );

    constructor() {
        DOMAIN_SEPARATOR = EIP712Domain.domainSeparator("SignedVoucherNetting", "1", block.chainid, address(this));
    }

    function voucherDigest(Voucher calldata v) external view returns (bytes32) {
        return _digest(v);
    }

    receive() external payable {}

    function redeem(Voucher calldata v, bytes calldata signature) external {
        if (v.amount == 0) revert InvalidAmount();
        if (block.timestamp > v.expiresAt) revert VoucherExpired();
        if (consumed[v.payer][v.nonce]) revert AlreadyConsumed();
        bytes32 digest = _digest(v);
        address recovered = Signatures.recoverEOA(digest, signature);
        if (recovered != v.payer) revert InvalidSignature();
        consumed[v.payer][v.nonce] = true;
        (bool ok,) = v.recipient.call{value: v.amount}("");
        if (!ok) revert TransferFailed();
        emit VoucherRedeemed(v.payer, v.recipient, v.sessionId, v.amount, v.nonce);
    }

    function _digest(Voucher calldata v) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(VOUCHER_TYPEHASH, v.payer, v.recipient, v.sessionId, v.amount, v.nonce, v.expiresAt)
        );
        return EIP712Domain.hashTypedData(DOMAIN_SEPARATOR, structHash);
    }
}
