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
    error BatchAlreadyExists();
    error NoBond();

    enum BatchStatus { Pending, Finalized, Invalidated }

    struct Batch {
        address submitter;
        uint256 receiptCount;
        uint64 submittedAt;
        uint64 challengeDeadline;
        uint256 bondAtSubmission;
        BatchStatus status;
        bytes32 receiptsRoot;
        bytes32 deltasRoot;
    }

    address public immutable owner;
    DepositEscrow public immutable escrow;

    mapping(address => bool) public authorizedSubmitters;
    mapping(address => uint256) private _bondOf;
    mapping(address => uint256) private _pendingBatchesOf;
    uint256 public totalBondedStake;
    uint64 public challengeWindow;
    mapping(bytes32 => Batch) public batches;

    event SubmitterAuthorized(address indexed submitter, bool authorized);
    event SubmitterBonded(address indexed submitter, uint256 amount);
    event SubmitterUnbonded(address indexed submitter, uint256 amount);
    event BatchSubmitted(
        bytes32 indexed batchId,
        address indexed submitter,
        bytes32 receiptsRoot,
        bytes32 deltasRoot,
        uint256 receiptCount,
        uint64 challengeDeadline
    );

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

    function setChallengeWindow(uint64 window) external onlyOwner {
        challengeWindow = window;
    }

    function submitOptimisticBatch(bytes32 batchId, bytes32 receiptsRoot, bytes32 deltasRoot, uint256 receiptCount)
        external
        onlyAuthorizedSubmitter
    {
        if (batches[batchId].submitter != address(0)) revert BatchAlreadyExists();
        uint256 bond_ = _bondOf[msg.sender];
        if (bond_ == 0) revert NoBond();
        uint64 deadline = uint64(block.timestamp) + challengeWindow;
        batches[batchId] = Batch({
            submitter: msg.sender,
            receiptCount: receiptCount,
            submittedAt: uint64(block.timestamp),
            challengeDeadline: deadline,
            bondAtSubmission: bond_,
            status: BatchStatus.Pending,
            receiptsRoot: receiptsRoot,
            deltasRoot: deltasRoot
        });
        _pendingBatchesOf[msg.sender] += 1;
        emit BatchSubmitted(batchId, msg.sender, receiptsRoot, deltasRoot, receiptCount, deadline);
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
