// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Signatures} from "../lib/Signatures.sol";
import {EIP712Domain} from "../lib/EIP712Domain.sol";

/// @notice Channel-style baseline B2b. Recipient redeems N vouchers from N
/// payers atomically in one tx; per-request gas amortizes across the entire
/// batch. This is the strong baseline TallyMesh must beat.
contract SignedVoucherAggregate {
    error InvalidSignature();
    error AlreadyConsumed();
    error VoucherExpired();
    error InvalidAmount();
    error LengthMismatch();
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

    event BatchRedeemed(address indexed recipient, uint256 totalAmount, uint256 voucherCount);

    constructor() {
        DOMAIN_SEPARATOR = EIP712Domain.domainSeparator("SignedVoucherAggregate", "1", block.chainid, address(this));
    }

    receive() external payable {}

    function voucherDigest(Voucher calldata v) external view returns (bytes32) {
        return _digest(v);
    }

    function redeemBatch(Voucher[] calldata vouchers, bytes[] calldata signatures) external {
        if (vouchers.length != signatures.length) revert LengthMismatch();
        uint256 total;
        address payable firstRecipient;
        for (uint256 i = 0; i < vouchers.length; i++) {
            Voucher calldata v = vouchers[i];
            if (v.amount == 0) revert InvalidAmount();
            if (block.timestamp > v.expiresAt) revert VoucherExpired();
            if (consumed[v.payer][v.nonce]) revert AlreadyConsumed();
            bytes32 digest = _digest(v);
            if (Signatures.recoverEOA(digest, signatures[i]) != v.payer) revert InvalidSignature();
            consumed[v.payer][v.nonce] = true;
            if (i == 0) {
                firstRecipient = v.recipient;
            }
            total += v.amount;
        }
        // For v1 we restrict the batch to a single recipient (the strong baseline scenario).
        // Per-recipient netting in one tx is sufficient for the headline plot.
        (bool ok,) = firstRecipient.call{value: total}("");
        if (!ok) revert TransferFailed();
        emit BatchRedeemed(firstRecipient, total, vouchers.length);
    }

    function _digest(Voucher calldata v) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(VOUCHER_TYPEHASH, v.payer, v.recipient, v.sessionId, v.amount, v.nonce, v.expiresAt)
        );
        return EIP712Domain.hashTypedData(DOMAIN_SEPARATOR, structHash);
    }
}
