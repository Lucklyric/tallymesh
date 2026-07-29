// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Read interface to ServiceRegistry for downstream consumers.
interface IServiceRegistry {
    function services(bytes32 serviceId)
        external
        view
        returns (address owner, bool active, bytes32 metadataHash, bytes32 feeScheduleHash);

    function isServiceSigner(bytes32 serviceId, address signer) external view returns (bool);
}
