// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {DepositEscrow} from "./DepositEscrow.sol";
import {ReceiptLib} from "./lib/ReceiptLib.sol";
import {EIP712Domain} from "./lib/EIP712Domain.sol";
import {Signatures} from "./lib/Signatures.sol";
import {IBatchVerifier} from "./interfaces/IBatchVerifier.sol";

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
    error SessionAlreadyOpen();
    error SessionNotFound();
    error InvalidRecipient();
    error InvalidAmount();
    error BatchNotFound();
    error BatchNotFinalized();
    error BatchAlreadyFinalized();
    error ChallengeWindowOpen();
    error InvalidReceiptProof();
    error ReceiptAlreadyClaimed();
    error NotDisputeManager();
    error InvalidationNotAllowed();
    error VerifierNotApproved();
    error InvalidValidityProof();
    error ClaimRequiresOptimisticMode();
    error InvalidSessionIntentSignature();
    error SessionIntentExpired();
    error SessionIntentOverBudget();
    error LegacyReserveDisabled();
    error BlobNotPresent();
    error BlobHashMismatch();
    error ArrayLengthMismatch();
    error MixedSessionsNotAllowed();
    error EmptyClaimBatch();

    enum BatchStatus { Pending, Finalized, Invalidated }
    enum SettlementMode { Optimistic, ZK }

    struct Session {
        address payer;
        address payable recipient;
        uint256 amount;
        bool open;
    }

    struct SessionIntent {
        bytes32 sessionId;
        address payer;
        address payable recipient;
        uint256 amount;
        uint256 maxAmount;
        uint64 expiry;
    }

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
    bytes32 public immutable DOMAIN_SEPARATOR;

    bytes32 internal constant SESSION_INTENT_TYPEHASH = keccak256(
        "SessionIntent(bytes32 sessionId,address payer,address recipient,uint256 amount,uint256 maxAmount,uint64 expiry)"
    );

    uint256 public constant BURN_BPS = 5000;
    uint256 private constant BPS_DENOMINATOR = 10_000;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    mapping(address => bool) public authorizedSubmitters;
    mapping(address => uint256) private _bondOf;
    mapping(address => uint256) private _pendingBatchesOf;
    uint256 public totalBondedStake;
    uint64 public challengeWindow;
    mapping(bytes32 => Batch) public batches;
    mapping(bytes32 => Session) public sessions;
    // Global receipt-claim key keyed by keccak256(sessionId, seq, requestHash).
    mapping(bytes32 => bool) public claimedReceipt;
    address public disputeManager;
    mapping(bytes32 => SettlementMode) public settlementModeOf;
    mapping(bytes32 => address) public verifierOf;
    mapping(address => bool) public approvedVerifiers;
    uint256 public chargedCeiling;
    bool public legacyReserveEnabled;

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
    event SessionReserved(bytes32 indexed sessionId, address indexed payer, address indexed recipient, uint256 amount);
    event BatchFinalized(bytes32 indexed batchId);
    event ReceiptClaimed(bytes32 indexed batchId, bytes32 indexed receiptKey, address payer, address recipient, uint256 amount);
    event VerifierApproved(address indexed verifier, bool approved);
    event ChargedCeilingUpdated(uint256 newCeiling);
    event LegacyReserveToggled(bool enabled);
    event ZkBatchSubmitted(
        bytes32 indexed batchId,
        address indexed submitter,
        address indexed verifier,
        bytes32 receiptsRoot,
        uint256 receiptCount
    );
    event ReceiptsBatchClaimed(
        bytes32 indexed batchId,
        bytes32 indexed sessionId,
        address indexed recipient,
        uint256 count,
        uint256 totalAmount
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
        DOMAIN_SEPARATOR = EIP712Domain.domainSeparator("TallyMesh", "1", block.chainid, address(this));
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

    function setDisputeManager(address dispute_) external onlyOwner {
        disputeManager = dispute_;
    }

    function setApprovedVerifier(address verifier, bool approved) external onlyOwner {
        approvedVerifiers[verifier] = approved;
        emit VerifierApproved(verifier, approved);
    }

    function setChargedCeiling(uint256 newCeiling) external onlyOwner {
        chargedCeiling = newCeiling;
        emit ChargedCeilingUpdated(newCeiling);
    }

    function setLegacyReserveEnabled(bool enabled) external onlyOwner {
        legacyReserveEnabled = enabled;
        emit LegacyReserveToggled(enabled);
    }

    function invalidateAndSlash(bytes32 batchId, address payable challenger) external {
        if (msg.sender != disputeManager) revert NotDisputeManager();
        _invalidateBatch(batchId, challenger);
    }

    /// @notice Invalidates only `batchId` and splits the slashed bond 50/50
    /// between the challenger and burn address. Other pending batches from the
    /// same submitter remain in flight so disputes stay scoped per batch.
    function _invalidateBatch(bytes32 batchId, address payable challenger) internal {
        Batch storage b = batches[batchId];
        if (b.submitter == address(0)) revert BatchNotFound();
        if (b.status != BatchStatus.Pending) revert InvalidationNotAllowed();
        b.status = BatchStatus.Invalidated;
        if (_pendingBatchesOf[b.submitter] > 0) {
            _pendingBatchesOf[b.submitter] -= 1;
        }
        uint256 slashed = _bondOf[b.submitter];
        _bondOf[b.submitter] = 0;
        totalBondedStake -= slashed;
        emit SubmitterUnbonded(b.submitter, slashed);
        if (slashed > 0) {
            uint256 burnAmount = (slashed * BURN_BPS) / BPS_DENOMINATOR;
            uint256 challengerAmount = slashed - burnAmount;
            (bool ok,) = challenger.call{value: challengerAmount}("");
            if (!ok) revert TransferFailed();
            (ok,) = payable(BURN_ADDRESS).call{value: burnAmount}("");
            if (!ok) revert TransferFailed();
        }
    }

    /// @dev v0; prefer reserveSessionWithIntent.
    function reserveSession(bytes32 sessionId, address payable recipient, uint256 amount) external {
        if (!legacyReserveEnabled) revert LegacyReserveDisabled();
        _reserveSession(sessionId, msg.sender, recipient, amount);
    }

    function reserveSessionWithIntent(SessionIntent calldata intent, bytes calldata sig) external {
        bytes32 digest = EIP712Domain.hashTypedData(DOMAIN_SEPARATOR, _hashSessionIntent(intent));
        address signer = Signatures.recoverEOA(digest, sig);
        if (signer != intent.payer) revert InvalidSessionIntentSignature();
        if (block.timestamp > intent.expiry) revert SessionIntentExpired();
        if (intent.maxAmount < intent.amount) revert SessionIntentOverBudget();
        _reserveSession(intent.sessionId, intent.payer, intent.recipient, intent.amount);
    }

    function _hashSessionIntent(SessionIntent calldata intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                SESSION_INTENT_TYPEHASH,
                intent.sessionId,
                intent.payer,
                intent.recipient,
                intent.amount,
                intent.maxAmount,
                intent.expiry
            )
        );
    }

    function _reserveSession(bytes32 sessionId, address payer, address payable recipient, uint256 amount) internal {
        if (sessions[sessionId].open) revert SessionAlreadyOpen();
        if (recipient == address(0)) revert InvalidRecipient();
        if (amount == 0) revert InvalidAmount();
        sessions[sessionId] = Session({payer: payer, recipient: recipient, amount: amount, open: true});
        escrow.reserve(sessionId, payer, amount);
        emit SessionReserved(sessionId, payer, recipient, amount);
    }

    /// @param expectedBlobHash EIP-4844 versioned hash for blob 0 in this transaction.
    /// SDK callers that do not hold a KZG commitment helper should obtain this
    /// externally from the blob-carrying transaction/block and pass it here.
    function submitOptimisticBatch(
        bytes32 batchId,
        bytes32 receiptsRoot,
        bytes32 deltasRoot,
        uint256 receiptCount,
        bytes32 expectedBlobHash
    ) external onlyAuthorizedSubmitter {
        if (batches[batchId].submitter != address(0)) revert BatchAlreadyExists();
        uint256 bond_ = _bondOf[msg.sender];
        if (bond_ == 0) revert NoBond();
        bytes32 actualBlobHash;
        assembly {
            actualBlobHash := blobhash(0)
        }
        if (actualBlobHash == bytes32(0)) revert BlobNotPresent();
        if (actualBlobHash != expectedBlobHash) revert BlobHashMismatch();
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

    function submitZkBatch(
        bytes32 batchId,
        bytes32 receiptsRoot,
        bytes32 deltasRoot,
        uint256 receiptCount,
        address verifier,
        bytes calldata proof
    ) external onlyAuthorizedSubmitter {
        if (batches[batchId].submitter != address(0)) revert BatchAlreadyExists();
        if (!approvedVerifiers[verifier]) revert VerifierNotApproved();
        if (!IBatchVerifier(verifier).verifyBatch(receiptsRoot, receiptCount, chargedCeiling, proof)) {
            revert InvalidValidityProof();
        }
        batches[batchId] = Batch({
            submitter: msg.sender,
            receiptCount: receiptCount,
            submittedAt: uint64(block.timestamp),
            challengeDeadline: uint64(block.timestamp), // immediate finality
            bondAtSubmission: _bondOf[msg.sender],
            status: BatchStatus.Finalized,
            receiptsRoot: receiptsRoot,
            deltasRoot: deltasRoot
        });
        settlementModeOf[batchId] = SettlementMode.ZK;
        verifierOf[batchId] = verifier;
        // Note: no _pendingBatchesOf increment; ZK batches have no pending state.
        emit ZkBatchSubmitted(batchId, msg.sender, verifier, receiptsRoot, receiptCount);
        emit BatchSubmitted(batchId, msg.sender, receiptsRoot, deltasRoot, receiptCount, uint64(block.timestamp));
        emit BatchFinalized(batchId);
    }

    function bondOf(address submitter) external view returns (uint256) {
        return _bondOf[submitter];
    }

    function pendingBatchesOf(address submitter) external view returns (uint256) {
        return _pendingBatchesOf[submitter];
    }

    function finalizeBatch(bytes32 batchId) external {
        Batch storage b = batches[batchId];
        if (b.submitter == address(0)) revert BatchNotFound();
        if (b.status == BatchStatus.Finalized) revert BatchAlreadyFinalized();
        if (b.status == BatchStatus.Invalidated) revert BatchNotFound();
        if (block.timestamp < b.challengeDeadline) revert ChallengeWindowOpen();
        b.status = BatchStatus.Finalized;
        if (_pendingBatchesOf[b.submitter] > 0) {
            _pendingBatchesOf[b.submitter] -= 1;
        }
        emit BatchFinalized(batchId);
    }

    function claimPayout(bytes32 batchId, ReceiptLib.Receipt calldata receipt, bytes32[] calldata proof) external {
        if (settlementModeOf[batchId] != SettlementMode.Optimistic) revert ClaimRequiresOptimisticMode();
        Batch storage b = batches[batchId];
        if (b.status != BatchStatus.Finalized) revert BatchNotFinalized();
        Session storage s = sessions[receipt.sessionId];
        if (!s.open) revert SessionNotFound();
        bytes32 leaf = ReceiptLib.leafHash(receipt);
        if (!ReceiptLib.verifyProof(proof, b.receiptsRoot, leaf)) revert InvalidReceiptProof();
        bytes32 receiptKey = keccak256(abi.encode(receipt.sessionId, receipt.seq, receipt.requestHash));
        if (claimedReceipt[receiptKey]) revert ReceiptAlreadyClaimed();
        claimedReceipt[receiptKey] = true;
        escrow.settleReserved(receipt.sessionId, s.payer, s.recipient, receipt.chargedAmount);
        emit ReceiptClaimed(batchId, receiptKey, s.payer, s.recipient, receipt.chargedAmount);
    }

    /// @notice Claim multiple receipts from one batch sharing a single session in one call.
    /// All receipts must reference the same `sessionId`; the escrow settlement and the recipient
    /// transfer happen exactly once at the end. The per-receipt `claimedReceipt[]` keys are
    /// shared with `claimPayout`, so a receipt claimed via either path cannot be re-claimed.
    function claimPayoutBatch(
        bytes32 batchId,
        ReceiptLib.Receipt[] calldata receipts,
        bytes32[][] calldata proofs
    ) external {
        if (settlementModeOf[batchId] != SettlementMode.Optimistic) revert ClaimRequiresOptimisticMode();
        uint256 n = receipts.length;
        if (n == 0) revert EmptyClaimBatch();
        if (n != proofs.length) revert ArrayLengthMismatch();
        Batch storage b = batches[batchId];
        if (b.status != BatchStatus.Finalized) revert BatchNotFinalized();

        bytes32 sharedSessionId = receipts[0].sessionId;
        Session storage s = sessions[sharedSessionId];
        if (!s.open) revert SessionNotFound();
        bytes32 root = b.receiptsRoot;
        address payer = s.payer;
        address payable recipient = s.recipient;
        uint256 totalAmount;

        for (uint256 i = 0; i < n; ++i) {
            ReceiptLib.Receipt calldata r = receipts[i];
            if (r.sessionId != sharedSessionId) revert MixedSessionsNotAllowed();
            bytes32 leaf = ReceiptLib.leafHash(r);
            if (!ReceiptLib.verifyProof(proofs[i], root, leaf)) revert InvalidReceiptProof();
            bytes32 receiptKey = keccak256(abi.encode(r.sessionId, r.seq, r.requestHash));
            if (claimedReceipt[receiptKey]) revert ReceiptAlreadyClaimed();
            claimedReceipt[receiptKey] = true;
            totalAmount += r.chargedAmount;
        }

        escrow.settleReserved(sharedSessionId, payer, recipient, totalAmount);
        emit ReceiptsBatchClaimed(batchId, sharedSessionId, recipient, n, totalAmount);
    }

}
