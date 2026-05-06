// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ServiceRegistry} from "./ServiceRegistry.sol";

/// @notice Per-service role/resource policy and issuer-role binding registry.
contract RolePolicyRegistry {
    error NotServiceOwner();

    struct Policy {
        uint256 maxPerCall;
        bool enabled;
    }

    ServiceRegistry public immutable services;

    // service => resource => role => Policy
    mapping(bytes32 => mapping(bytes32 => mapping(bytes32 => Policy))) private _policy;
    // service => role => issuer => bool
    mapping(bytes32 => mapping(bytes32 => mapping(bytes32 => bool))) private _issuerBound;

    event RolePolicyUpdated(
        bytes32 indexed serviceId, bytes32 indexed resource, bytes32 indexed role, uint256 maxPerCall, bool enabled
    );
    event IssuerBindingUpdated(bytes32 indexed serviceId, bytes32 indexed role, bytes32 issuerId, bool enabled);

    constructor(address serviceRegistry_) {
        services = ServiceRegistry(serviceRegistry_);
    }

    modifier onlyServiceOwner(bytes32 serviceId) {
        (address owner,,,) = services.services(serviceId);
        if (owner != msg.sender) revert NotServiceOwner();
        _;
    }

    function setRolePolicy(bytes32 serviceId, bytes32 resource, bytes32 role, uint256 maxPerCall, bool enabled)
        external
        onlyServiceOwner(serviceId)
    {
        _policy[serviceId][resource][role] = Policy({maxPerCall: maxPerCall, enabled: enabled});
        emit RolePolicyUpdated(serviceId, resource, role, maxPerCall, enabled);
    }

    function setIssuerBinding(bytes32 serviceId, bytes32 role, bytes32 issuerId, bool enabled)
        external
        onlyServiceOwner(serviceId)
    {
        _issuerBound[serviceId][role][issuerId] = enabled;
        emit IssuerBindingUpdated(serviceId, role, issuerId, enabled);
    }

    function policy(bytes32 serviceId, bytes32 resource, bytes32 role)
        external
        view
        returns (uint256 maxPerCall, bool enabled)
    {
        Policy storage p = _policy[serviceId][resource][role];
        return (p.maxPerCall, p.enabled);
    }

    function isIssuerBound(bytes32 serviceId, bytes32 role, bytes32 issuerId) external view returns (bool) {
        return _issuerBound[serviceId][role][issuerId];
    }
}
