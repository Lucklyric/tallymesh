// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Canonical EIP-712 domain separator for TallyMesh signed messages.
library EIP712Domain {
    bytes32 internal constant TYPE_HASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );

    function domainSeparator(string memory name, string memory version, uint256 chainId, address verifyingContract)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                TYPE_HASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
    }

    function hashTypedData(bytes32 separator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(hex"1901", separator, structHash));
    }
}
