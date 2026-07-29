// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Registry of decentralized routers. Each router self-registers,
/// posts a bond, and publishes hash commitments to its catalog and pricing
/// schedule. Bond may be slashed by future routing-evidence dispute logic
/// (Day 4b sdk-ts routing receipts); for Day 4a only registration and
/// owner-managed lifecycle are implemented.
contract RouterRegistry {
    error RouterAlreadyRegistered();
    error RouterNotRegistered();
    error NotRouterOwner();
    error RouterStillActive();
    error NoBond();
    error TransferFailed();

    struct Router {
        address owner;
        bool active;
        bytes32 catalogHash;
        bytes32 pricingHash;
        uint256 bond;
    }

    mapping(bytes32 => Router) public routers;

    event RouterRegistered(bytes32 indexed routerId, address indexed owner, bytes32 catalogHash, bytes32 pricingHash, uint256 bond);
    event RouterBondAdded(bytes32 indexed routerId, uint256 amount, uint256 newBond);
    event RouterCatalogUpdated(bytes32 indexed routerId, bytes32 catalogHash);
    event RouterPricingUpdated(bytes32 indexed routerId, bytes32 pricingHash);
    event RouterDeactivated(bytes32 indexed routerId);
    event RouterBondWithdrawn(bytes32 indexed routerId, uint256 amount);

    modifier onlyRouterOwner(bytes32 routerId) {
        if (routers[routerId].owner == address(0)) revert RouterNotRegistered();
        if (routers[routerId].owner != msg.sender) revert NotRouterOwner();
        _;
    }

    function registerRouter(bytes32 routerId, bytes32 catalogHash, bytes32 pricingHash) external payable {
        if (routers[routerId].owner != address(0)) revert RouterAlreadyRegistered();
        if (msg.value == 0) revert NoBond();
        routers[routerId] = Router({
            owner: msg.sender,
            active: true,
            catalogHash: catalogHash,
            pricingHash: pricingHash,
            bond: msg.value
        });
        emit RouterRegistered(routerId, msg.sender, catalogHash, pricingHash, msg.value);
    }

    function addBond(bytes32 routerId) external payable onlyRouterOwner(routerId) {
        routers[routerId].bond += msg.value;
        emit RouterBondAdded(routerId, msg.value, routers[routerId].bond);
    }

    function updateCatalog(bytes32 routerId, bytes32 catalogHash) external onlyRouterOwner(routerId) {
        routers[routerId].catalogHash = catalogHash;
        emit RouterCatalogUpdated(routerId, catalogHash);
    }

    function updatePricing(bytes32 routerId, bytes32 pricingHash) external onlyRouterOwner(routerId) {
        routers[routerId].pricingHash = pricingHash;
        emit RouterPricingUpdated(routerId, pricingHash);
    }

    function deactivateRouter(bytes32 routerId) external onlyRouterOwner(routerId) {
        routers[routerId].active = false;
        emit RouterDeactivated(routerId);
    }

    function withdrawBond(bytes32 routerId) external onlyRouterOwner(routerId) {
        if (routers[routerId].active) revert RouterStillActive();
        uint256 amount = routers[routerId].bond;
        routers[routerId].bond = 0;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit RouterBondWithdrawn(routerId, amount);
    }
}
