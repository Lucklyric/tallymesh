// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DepositEscrow} from "./DepositEscrow.sol";

/// @notice Optimistic batch-settlement contract for TallyMesh receipts.
/// @dev v2 plan: bond management with unbond-locked-during-pending-batches.
/// Subsequent tasks add submitOptimisticBatch (Task 4), reserveSession
/// (Task 5), finalizeBatch / claimPayout (Task 6), and the disputeManager
/// hook (Task 7).
contract BatchSettlement {
    error NotOwner();
    error NotAuthorizedSubmitter();
    error InsufficientBond();
    error PendingBatchesPreventUnbond();
    error TransferFailed();

    address public immutable owner;
    DepositEscrow public immutable escrow;

    mapping(address => bool) public authorizedSubmitters;
    mapping(address => uint256) private _bondOf;
    mapping(address => uint256) private _pendingBatchesOf;
    uint256 public totalBondedStake;

    event SubmitterAuthorized(address indexed submitter, bool authorized);
    event SubmitterBonded(address indexed submitter, uint256 amount);
    event SubmitterUnbonded(address indexed submitter, uint256 amount);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAuthorizedSubmitter() {
        if (!authorizedSubmitters[msg.sender]) revert NotAuthorizedSubmitter();
        _;
    }

    constructor(address escrow_) {
        owner = msg.sender;
        escrow = DepositEscrow(escrow_);
    }

    function setAuthorizedSubmitter(address submitter, bool authorized) external onlyOwner {
        authorizedSubmitters[submitter] = authorized;
        emit SubmitterAuthorized(submitter, authorized);
    }

    function bond() external payable onlyAuthorizedSubmitter {
        _bondOf[msg.sender] += msg.value;
        totalBondedStake += msg.value;
        emit SubmitterBonded(msg.sender, msg.value);
    }

    function unbond(uint256 amount) external {
        if (_pendingBatchesOf[msg.sender] > 0) revert PendingBatchesPreventUnbond();
        if (_bondOf[msg.sender] < amount) revert InsufficientBond();
        _bondOf[msg.sender] -= amount;
        totalBondedStake -= amount;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit SubmitterUnbonded(msg.sender, amount);
    }

    function bondOf(address submitter) external view returns (uint256) {
        return _bondOf[submitter];
    }

    function pendingBatchesOf(address submitter) external view returns (uint256) {
        return _pendingBatchesOf[submitter];
    }

    /// @dev Test-only hook used to exercise the unbond-locked invariant before
    /// the submit/finalize lifecycle is wired up. The `onlyOwner` gate prevents
    /// any non-deployer from abusing it; the function is harmless in production
    /// because no honest deployment grants `pendingBatchesOf` arbitrary values.
    /// Future hardening: remove this hook entirely after Day 4 once the SDK
    /// integration has full coverage.
    function debugSetPendingBatches(address submitter, uint256 count) external onlyOwner {
        _pendingBatchesOf[submitter] = count;
    }
}
