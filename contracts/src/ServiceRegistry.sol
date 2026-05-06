// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Registry of services and their owner-rotatable signer sets.
contract ServiceRegistry {
    error ServiceAlreadyRegistered();
    error ServiceNotRegistered();
    error NotServiceOwner();

    struct Service {
        address owner;
        bool active;
        bytes32 metadataHash;
        bytes32 feeScheduleHash;
    }

    mapping(bytes32 => Service) public services;
    mapping(bytes32 => mapping(address => bool)) private _signerOf;

    event ServiceRegistered(bytes32 indexed serviceId, address indexed owner, bytes32 metadataHash, bytes32 feeScheduleHash);
    event ServiceSignerUpdated(bytes32 indexed serviceId, address indexed signer, bool enabled);
    event ServiceDeactivated(bytes32 indexed serviceId);

    modifier onlyServiceOwner(bytes32 serviceId) {
        if (services[serviceId].owner == address(0)) revert ServiceNotRegistered();
        if (services[serviceId].owner != msg.sender) revert NotServiceOwner();
        _;
    }

    function registerService(bytes32 serviceId, bytes32 metadataHash, bytes32 feeScheduleHash) external {
        if (services[serviceId].owner != address(0)) revert ServiceAlreadyRegistered();
        services[serviceId] = Service({
            owner: msg.sender,
            active: true,
            metadataHash: metadataHash,
            feeScheduleHash: feeScheduleHash
        });
        emit ServiceRegistered(serviceId, msg.sender, metadataHash, feeScheduleHash);
    }

    function setServiceSigner(bytes32 serviceId, address signer, bool enabled) external onlyServiceOwner(serviceId) {
        _signerOf[serviceId][signer] = enabled;
        emit ServiceSignerUpdated(serviceId, signer, enabled);
    }

    function deactivateService(bytes32 serviceId) external onlyServiceOwner(serviceId) {
        services[serviceId].active = false;
        emit ServiceDeactivated(serviceId);
    }

    function isServiceSigner(bytes32 serviceId, address signer) external view returns (bool) {
        return _signerOf[serviceId][signer];
    }
}
