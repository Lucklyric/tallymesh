// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @notice Thin wrapper over OpenZeppelin ECDSA + ERC-1271. Canonical-s is
/// enforced by OZ ECDSA itself (it reverts with `ECDSAInvalidSignatureS`).
/// We deliberately do NOT hand-roll signature parsing for a 10-day paper
/// deadline — signature handling is not the contribution.
library Signatures {
    bytes4 private constant ERC1271_MAGIC = 0x1626ba7e;

    function recoverEOA(bytes32 digest, bytes memory signature) internal pure returns (address) {
        return ECDSA.recover(digest, signature);
    }

    function isValidContractSignature(address account, bytes32 digest, bytes memory signature)
        internal
        view
        returns (bool)
    {
        try IERC1271(account).isValidSignature(digest, signature) returns (bytes4 magic) {
            return magic == ERC1271_MAGIC;
        } catch {
            return false;
        }
    }
}
