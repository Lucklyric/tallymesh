// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Native-ETH escrow with per-session reservations.
/// @dev Native ETH only for the BCCA submission; multi-token is out of scope.
/// @dev Settlers are owner-managed (not immutable) so that BatchSettlement,
/// DisputeManager, and each Day-5 baseline can be authorized as separate
/// settlement adapters against the same escrow without redeploying.
contract DepositEscrow {
    error NotOwner();
    error NotAuthorizedSettler();
    error InsufficientFreeBalance();
    error InsufficientReserved();
    error TransferFailed();

    address public immutable owner;
    mapping(address => bool) public authorizedSettlers;

    mapping(address => uint256) private _free;
    mapping(bytes32 => mapping(address => uint256)) private _reserved;

    event Deposited(address indexed payer, uint256 amount);
    event Withdrawn(address indexed payer, address indexed to, uint256 amount);
    event Reserved(bytes32 indexed sessionId, address indexed payer, uint256 amount);
    event Released(bytes32 indexed sessionId, address indexed payer, uint256 amount);
    event Settled(bytes32 indexed sessionId, address indexed payer, address indexed recipient, uint256 amount);
    event SettlerAuthorized(address indexed settler, bool authorized);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlySettler() {
        if (!authorizedSettlers[msg.sender]) revert NotAuthorizedSettler();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setAuthorizedSettler(address settler, bool authorized) external onlyOwner {
        authorizedSettlers[settler] = authorized;
        emit SettlerAuthorized(settler, authorized);
    }

    function deposit() external payable {
        _free[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function withdraw(uint256 amount, address payable to) external {
        if (_free[msg.sender] < amount) revert InsufficientFreeBalance();
        _free[msg.sender] -= amount;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawn(msg.sender, to, amount);
    }

    function reserve(bytes32 sessionId, address payer, uint256 amount) external onlySettler {
        if (_free[payer] < amount) revert InsufficientFreeBalance();
        _free[payer] -= amount;
        _reserved[sessionId][payer] += amount;
        emit Reserved(sessionId, payer, amount);
    }

    function release(bytes32 sessionId, address payer, uint256 amount) external onlySettler {
        if (_reserved[sessionId][payer] < amount) revert InsufficientReserved();
        _reserved[sessionId][payer] -= amount;
        _free[payer] += amount;
        emit Released(sessionId, payer, amount);
    }

    function settleReserved(bytes32 sessionId, address payer, address payable recipient, uint256 amount)
        external
        onlySettler
    {
        if (_reserved[sessionId][payer] < amount) revert InsufficientReserved();
        _reserved[sessionId][payer] -= amount;
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Settled(sessionId, payer, recipient, amount);
    }

    function balanceOf(address payer) external view returns (uint256) {
        return _free[payer];
    }

    function reservedOf(bytes32 sessionId, address payer) external view returns (uint256) {
        return _reserved[sessionId][payer];
    }
}
