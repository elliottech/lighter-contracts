// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "../Storage.sol";
import "./IEvents.sol";
import "../lib/TxTypes.sol";

/// @title zkLighter Interface
/// @author zkLighter Team
interface IZkLighter is IEvents {
  enum PubDataMode {
    Blob,
    Calldata
  }

  struct CommitBatchInfo {
    bytes32 newStateRoot;
    // Core
    bytes32 onChainOperationsHash;
    uint64 endBlockNumber;
    uint32 batchSize;
    uint64 startTimestamp;
    uint64 endTimestamp;
    bytes32 newCoreStateRoot;
    bytes32 newValidiumRoot;
    uint32 priorityRequestCount;
    bytes32 prefixPriorityRequestHash;
    // EVM
    uint256 endEvmBlockNumber;
    uint256 evmNumBlocks;
    bytes32 oldEvmBlockhash;
    bytes32 newEvmBlockhash;
    uint32 evmPriorityRequestCount;
    bytes32 prefixEvmPriorityRequestHash;
    uint32 initToCoreWritesCount;
    uint32 doneToCoreWritesCount;
    uint32 initToEvmWritesCount;
    uint32 doneToEvmWritesCount;
    bytes32 evmL1CallsRoot;
  }

  struct DesertBatchInfo {
    bytes32 newStateRoot;
    // EVM
    bytes32 oldEvmBlockhash;
    bytes32 newEvmBlockhash;
    uint32 evmPriorityRequestCount;
    bytes32 prefixEvmPriorityRequestHash;
    uint32 doneToCoreWritesCount;
    uint32 doneToEvmWritesCount;
    bytes32 evmL1CallsRoot;
  }

  struct LighterStateRootPreimage {
    bytes32 evmBlockHash;
    bytes32 toEvmWriteStreamRoot;
    bytes32 toCoreWriteStreamRoot;
    uint64 latestParentCoreBlockNumber;
  }

  /// @notice Thrown when given commit batch data is inconsistent with the last stored batch
  error ZkLighter_InvalidPubDataMode();

  /// @notice Thrown when given old EVM block hash doesn't match the last batch's end EVM block hash
  error ZkLighter_InvalidOldEvmBlockhash();

  /// @notice Thrown when given commit batch size is wrong
  error ZkLighter_InvalidBatchSize();

  /// @notice Thrown when given commit batch data is inconsistent with the last stored batch
  error ZkLighter_NonIncreasingTimestamp();

  /// @notice Thrown when given StoredBatchInfo hash doesn't match what is stored
  error ZkLighter_StoredBatchInfoMismatch();

  /// @notice Thrown when given priority request count is inconsistent with queued priority requests
  error ZkLighter_CommitBatchPriorityRequestCountMismatch();

  /// @notice Thrown when given evm priority request count is inconsistent with queued evm priority requests
  error ZkLighter_CommitBatchEvmPriorityRequestCountMismatch();

  /// @notice Thrown when given priority request prefix hash doesn't match
  error ZkLighter_PriorityRequestPrefixHashMismatch();

  /// @notice Thrown when given evm priority request prefix hash doesn't match
  error ZkLighter_EvmPriorityRequestPrefixHashMismatch();

  /// @notice Thrown when execute batches is called with different lengths of data
  error ZkLighter_ExecuteInputLengthMismatch();

  /// @notice Thrown when execute batches is called with input length greater than pending count
  error ZkLighter_ExecuteInputLengthGreaterThanPendingCount();

  /// @notice Thrown when revert batches is called on an already executed batch
  error ZkLighter_CannotRevertExecutedBatch();

  /// @notice Thrown when revert batches is called on the genesis batch
  error ZkLighter_CannotRevertGenesisBatch();

  /// @notice Thrown when given withdraw pubdata for a batch has invalid length
  error ZkLighter_InvalidPubDataLength();

  /// @notice Thrown when given withdraw pubdata for a batch has invalid data type
  error ZkLighter_InvalidPubDataType();

  /// @notice Thrown when given withdraw pubdata for a batch is invalid
  error ZkLighter_OnChainOperationsHashMismatch();

  /// @notice Thrown when implementation contract calls the initialise function on self
  error ZkLighter_CannotBeInitialisedByImpl();

  /// @notice Thrown when the initialisation parameters are invalid
  error ZkLighter_InvalidInitializeParameters();

  /// @notice Thrown when the upgrade parameters are invalid
  error ZkLighter_InvalidUpgradeParameters();

  /// @notice Thrown when requested amount is greater than the pending balance
  error ZkLighter_InvalidWithdrawAmount();

  /// @notice Thrown when the transferred amount is not a multiple of the tick size
  error ZkLighter_TransferredAmountNotMultipleOfTickSize();

  /// @notice Thrown when upgrade address(this) is the implementation
  error ZkLighter_OnlyProxyCanCallUpgrade();

  /// @notice Thrown when a restricted function which can be called only from zkLighterProxy is called by other address
  error ZkLighter_OnlyZkLighter();

  /// @notice thrown when ETH transfer fails
  error ZkLighter_ETHTransferFailed();

  /// @notice Thrown when rollup balance difference (before and after transfer) is bigger than `_maxAmount`
  error ZkLighter_RollUpBalanceBiggerThanMaxAmount();

  /// @notice Thrown when verifyBatch is called on a batch which is not yet committed
  error ZkLighter_CannotVerifyNonCommittedBatch();

  /// @notice Thrown when verifyBatch is called for invalid batch
  error ZkLighter_VerifyBatchNotInOrder();

  /// @notice Thrown when verifyBatch is called with invalid proof
  error ZkLighter_VerifyBatchProofFailed();

  /// @notice Thrown when given batch is not yet verified
  error ZkLighter_CannotExecuteNonVerifiedBatch();

  /// @notice Thrown when given batch either doesn't contain on chain operations or the order is wrong
  error ZkLighter_BatchNotInOnChainQueue();

  /// @notice ZkLighterImplementation cannot delegate to AdditionalZkLighter
  error ZkLighter_ImplCantDelegateToAddl();

  /// @notice Thrown when the point evaluation parameters are invalid
  error ZkLighter_InvalidPointEvaluationParams();

  /// @notice Thrown when the blob commitment parameters are invalid
  error ZkLighter_InvalidBlobCommitmentParams();

  error ZkLighter_InvalidAssetIndex();

  error ZkLighter_DesertError();

  error ZkLighter_InvalidAssetConfigParams();

  error ZkLighter_DesertModeInactive();

  error ZkLighter_DesertVerifyProofFailed();

  error ZkLighter_DesertRecipientMismatch();

  error ZkLighter_AccountAlreadyPerformedDesertForAsset();

  error ZkLighter_NoOutstandingDepositsForCancelation();

  error ZkLighter_DepositPubdataHashMismatch();

  /// @notice Thrown when a blob-processing transaction exceeds the maximum allowed blob count
  error ZkLighter_InvalidBlobCount(uint256);

  /// @notice Thrown when transferTokens is called with invalid parameters
  error ZkLighter_InvalidMigrationTransfer();

  /// @notice Thrown when setCoreMessaging is called but coreMessaging is already set
  error ZkLighter_CoreMessagingAlreadySet();

  /// @notice Thrown when setCoreMessaging is called with an invalid address
  error ZkLighter_InvalidCoreMessagingAddress();

  /// @notice Thrown when trying to append blobs to an already verified batch
  error ZkLighter_CannotAppendBlobsToVerifiedBatch();

  /// @notice Thrown when a desert-mode batch is submitted before the commit/verify/execute pipeline has caught up
  error ZkLighter_DesertPipelineNotCaughtUp();

  /// @notice Thrown when the SNARK proof for a desert-mode batch fails verification
  error ZkLighter_DesertBatchProofFailed();

  /// @notice Thrown when a batch is submitted but the corresponding verifier has not been configured
  error ZkLighter_VerifierNotSet();

  /// @notice Thrown when the desert-mode base batch predates the batch at desert-mode activation
  error ZkLighter_DesertBaseBatchTooOld();

  /// @notice Thrown when a desert-mode EVM batch does not strictly extend the EVM block number
  error ZkLighter_DesertNonIncreasingEvmBlockNumber();

  /// @notice Checks if Desert mode must be entered. If true - enters desert mode and emits DesertMode event
  /// @dev Desert mode must be entered in case of current L1 block timestamp is higher than the oldest priority request expiration timestamp
  /// @return bool Flag that is true if the desert mode must be entered
  function activateDesertMode() external returns (bool);

  /// @notice Performs the Desert Exit, can be called only when desertMode is active
  /// @param _accountIndex Account index of the user who is performing the desert exit
  /// @param _l1Address L1 address of the user who is performing the desert exit
  /// @param _assetIndex Asset index of the asset to be exited
  /// @param _totalBaseAmount Total base balance of the user for the asset to be exited
  /// @param proof Proof for the user assets
  function performDesert(uint48 _accountIndex, address _l1Address, uint32 _assetIndex, uint128 _totalBaseAmount, bytes calldata proof) external;

  /// @notice Cancels outstanding deposits, can be called only when desertMode is active
  /// @param _n Number of outstanding priority requests to be cancelled
  /// @param _priorityPubData Array of outstanding priority requests to be cancelled
  function cancelOutstandingDepositsForDesertMode(uint64 _n, bytes[] calldata _priorityPubData) external;

  /// @notice Reverts unverified batches
  /// @param _batchesToRevert Array of batches to be reverted
  /// @param _remainingBatch Last batch that is not reverted
  function revertBatches(Storage.StoredBatchInfo[] calldata _batchesToRevert, Storage.StoredBatchInfo calldata _remainingBatch) external;

  /// @notice Commit a new batch with at least one blob.
  /// @param newBatchData  New batch to be committed
  /// @param lastStoredBatch Last committed batch
  function commitBatch(
    CommitBatchInfo calldata newBatchData,
    Storage.StoredBatchInfo calldata lastStoredBatch,
    bytes calldata pubdataCommitments
  ) external;

  /// @notice Commit and verify a batch in desert mode.
  function desertVerifyBatch(DesertBatchInfo calldata newBatchData, Storage.StoredBatchInfo calldata baseStoredBatch, bytes calldata proof) external;

  /// @notice Append additional blobs to a committed, unverified batch.
  /// @param batch Current stored batch info for the committed batch
  /// @param previousAggregatedBlobCommitment Previously committed aggregate blob commitment for this batch
  /// @param oldStateRoot Old state root used in the currently stored batch commitment
  /// @param pubdataCommitments Additional blob commitments
  function appendBatchBlobs(
    Storage.StoredBatchInfo calldata batch,
    bytes32 previousAggregatedBlobCommitment,
    bytes32 oldStateRoot,
    bytes calldata pubdataCommitments
  ) external;

  /// @notice Execute on chain operations in a verified batch
  /// @param batches Array of batches that contains the on chain operations to be executed
  /// @param onChainOperationsPubData Array of on chain operations that are verified and to be executed
  function executeBatches(Storage.StoredBatchInfo[] calldata batches, bytes[] calldata onChainOperationsPubData) external;

  /// @notice Verify a committed batch alongside its validity proof
  /// @param batch Batch to be verified
  /// @param proof Proof for the batch
  function verifyBatch(Storage.StoredBatchInfo memory batch, bytes memory proof) external;

  /// @notice Change the Core state root
  /// @dev This will also update the derived Lighter state root which is
  /// supposed to commit to the Core state root
  /// @param _lastStoredBatch Last committed batch
  /// @param stateRootPreimage Preimage of the current Lighter state root excluding Core state root
  /// @param newCoreStateRoot New Core state root
  /// @param newValidiumRoot New validium root
  /// @param proof Proof for the Core state root change
  function updateCoreStateRoot(
    Storage.StoredBatchInfo calldata _lastStoredBatch,
    LighterStateRootPreimage calldata stateRootPreimage,
    bytes32 newCoreStateRoot,
    bytes32 newValidiumRoot,
    bytes calldata proof
  ) external;

  function nextEvmPriorityRequestId() external view returns (uint64);

  function addEvmPriorityRequest(
    address to,
    uint256 value,
    uint256 depositAmount,
    uint256 gasLimit,
    bool isCreation,
    address refundAddress,
    bytes memory data
  ) external payable;

  function l2Sender() external view returns (address);

  /// @notice Returns the last account index tracked by ZkLighter before account registration moved to L1CoreMessaging.
  /// @dev Read once by L1CoreMessagingInit to seed its own account counter; not updated afterwards.
  function DEPRECATED_lastAccountIndex() external view returns (uint48);

  /// @notice Account address to account id mapping (excluding system accounts)
  function addressToAccountIndex(address) external view returns (uint48);

  /// @notice Returns the EVM-originated L1-call Merkle root persisted for a verified batch
  /// @dev Zero if the batch has not been verified, was reverted, or has no EVM L1 calls
  function evmL1CallsRoots(uint64 batchNumber) external view returns (bytes32);

  /// @notice Executes a Core-originated L1 call whose hash batch execution persisted.
  function executeCoreL1Call(address l2Sender_, address target, uint256 value, uint256 msgNonce, bytes calldata data) external;

  /// @notice Executes an EVM-originated L1 call committed by an executed batch.
  function executeEvmL1Call(
    uint64 batchNumber,
    bytes32[] calldata proof,
    uint256 isLeft,
    address l2Sender_,
    address target,
    uint256 value,
    uint256 msgNonce,
    bytes calldata data
  ) external;

  function addPriorityRequestExt(
    address _sender,
    uint8 _pubdataType,
    bytes calldata _priorityRequest,
    bytes calldata _pubDataWithMetadata
  ) external payable;

  function computePriorityFee(uint256 gasLimit) external view returns (uint256);
}
