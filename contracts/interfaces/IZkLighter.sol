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
    uint64 endBlockNumber;
    uint32 batchSize;
    uint64 startTimestamp;
    uint64 endTimestamp;
    uint32 priorityRequestCount;
    bytes32 prefixPriorityRequestHash;
    bytes32 onChainOperationsHash;
    bytes32 newStateRoot;
    bytes32 newValidiumRoot;
    bytes pubdataCommitments;
  }

  /// @notice Thrown when given commit batch data is inconsistent with the last stored batch
  error ZkLighter_InvalidPubDataMode();

  /// @notice Thrown when given commit batch data is inconsistent with the last stored batch
  error ZkLighter_NonIncreasingBlockNumber();

  /// @notice Thrown when given commit batch size is wrong
  error ZkLighter_InvalidBatchSize();

  /// @notice Thrown when given commit batch data is inconsistent with the last stored batch
  error ZkLighter_NonIncreasingTimestamp();

  /// @notice Thrown when given StoredBatchInfo hash doesn't match what is stored
  error ZkLighter_StoredBatchInfoMismatch();

  /// @notice Thrown when given priority request count is inconsistent with queued priority requests
  error ZkLighter_CommitBatchPriorityRequestCountMismatch();

  /// @notice Thrown when given priority request prefix hash doesn't match
  error ZkLighter_PriorityRequestPrefixHashMismatch();

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

  /// @notice ZkLighterImplementation cannot delegate to AdditionalZkLigher
  error ZkLighter_ImplCantDelegateToAddl();

  /// @notice Thrown when the new treasury address is zero
  error ZkLighter_TreasuryCannotBeZero();

  /// @notice Thrown when the new treasury address is already in use
  error ZkLighter_TreasuryCannotBeInUse();

  /// @notice Thrown when the new insurance fund operator address is zero
  error ZkLighter_InsuranceFundOperatorCannotBeZero();

  /// @notice Thrown when the new insurance fund operator address is already in use
  error ZkLighter_InsuranceFundOperatorCannotBeInUse();

  /// @notice Thrown when the point evaluation parameters are invalid
  error ZkLighter_InvalidPointEvaluationParams();

  /// @notice Thrown when the blob commitment parameters are invalid
  error ZkLighter_InvalidBlobCommitmentParams();

  error ZkLighter_InvalidAssetIndex();

  error ZkLighter_InvalidAssetConfigParams();

  error ZkLighter_DesertError();

  error ZkLighter_DesertAddressNotRegistered();

  /// @notice Thrown when the number of blobs in a batch exceeds the maximum allowed
  error ZkLighter_InvalidBlobCount(uint256);

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
  function performDesert(uint48 _accountIndex, address _l1Address, uint16 _assetIndex, uint128 _totalBaseAmount, bytes calldata proof) external;

  /// @notice Cancels outstanding deposits, can be called only when desertMode is active
  /// @param _n Number of outstanding priority requests to be cancelled
  /// @param _priorityPubData Array of outstanding priority requests to be cancelled
  function cancelOutstandingDepositsForDesertMode(uint64 _n, bytes[] memory _priorityPubData) external;

  /// @notice Deposit to Lighter
  /// @param _assetIndex Asset index
  /// @param _routeType Route type
  /// @param _amount Token amount
  /// @param _to The receiver L1 address
  function deposit(address _to, uint16 _assetIndex, TxTypes.RouteType _routeType, uint256 _amount) external payable;

  /// @notice Deposit USDC to Lighter for multiple users
  /// @param _amount Array of USDC Token amounts
  /// @param _to Array of receiver L1 addresses
  /// @param _accountIndex Array of account index values, will be used in the future
  function depositBatch(uint64[] calldata _amount, address[] calldata _to, uint48[] calldata _accountIndex) external;

  function addPriorityRequestExt(address sender, uint8 pubdataType, bytes calldata priorityRequest, bytes calldata pubDataWithMetadata) external;

  /// @notice Register a new asset config
  /// @param assetIndex Asset index
  /// @param tokenAddress Token address
  /// @param withdrawalsEnabled Withdrawals enabled flag
  /// @param extensionMultiplier Extension multiplier of the asset, in [1, MAX_ASSET_EXTENSION_MULTIPLIER] (= type(uint56).max)
  /// @param tickSize Tick size of the asset, in [1, MAX_TICK_SIZE] (= type(uint128).max)
  /// @param depositCapTicks Deposit cap in ticks
  /// @param minDepositTicks Minimum deposit in ticks
  /// @dev This function is only callable by the governor
  function registerAssetConfig(
    uint16 assetIndex,
    address tokenAddress,
    uint8 withdrawalsEnabled,
    uint56 extensionMultiplier,
    uint128 tickSize,
    uint64 depositCapTicks,
    uint64 minDepositTicks
  ) external;

  /// @notice Update existing asset config
  /// @param assetIndex Asset index
  /// @param withdrawalsEnabled Withdrawals enabled flag
  /// @param depositCapTicks Deposit cap in ticks
  /// @param minDepositTicks Minimum deposit in ticks
  /// @dev This function is only callable by the governor
  function updateAssetConfig(uint16 assetIndex, uint8 withdrawalsEnabled, uint64 depositCapTicks, uint64 minDepositTicks) external;

  /// @notice Withdraws tokens from ZkLighter contract to the owner
  /// @param _owner Account address
  /// @param _assetIndex Asset index
  /// @param _baseAmount Base amount to withdraw
  function withdrawPendingBalance(address _owner, uint16 _assetIndex, uint128 _baseAmount) external;

  /// @notice Withdraws USDC tokens from ZkLighter contract to the owner (legacy)
  /// @param _owner Account address
  /// @param _baseAmount Base USDC amount to withdraw
  function withdrawPendingBalanceLegacy(address _owner, uint128 _baseAmount) external;

  /// @notice Sends tokens
  /// @param _token Token address
  /// @param _to Address of recipient
  /// @param _amount Amount of tokens to transfer
  /// @param _maxAmount Maximum possible amount of tokens to transfer to this account
  /// @return uint256 Amount of tokens transferred
  function transferERC20(IERC20 _token, address _to, uint256 _amount, uint256 _maxAmount) external returns (uint256);

  /// @notice Sends ETH
  /// @param _to Address of recipient
  /// @param _amount Amount of ETH to transfer
  /// @return uint256 Amount of ETH transferred
  function transferETH(address _to, uint256 _amount) external returns (uint256);

  /// @notice Reverts unverified batches
  /// @param _batchesToRevert Array of batches to be reverted
  /// @param _remainingBatch Last batch that is not reverted
  function revertBatches(Storage.StoredBatchInfo[] memory _batchesToRevert, Storage.StoredBatchInfo memory _remainingBatch) external;

  /// @notice Get pending balance that the user can withdraw
  /// @param _owner Owner account address
  /// @param _assetIndex Asset index
  /// @return uint128 Pending balance
  function getPendingBalance(address _owner, uint16 _assetIndex) external view returns (uint128);

  /// @notice Get pending balance that the user can withdraw in USDC (legacy)
  /// @param _owner Owner account address
  /// @return uint128 Pending USDC balance
  function getPendingBalanceLegacy(address _owner) external view returns (uint128);

  /// @notice Commit a new batch with at least one blob.
  /// @param newBatchData  New batch to be committed
  /// @param lastStoredBatch Last committed batch
  function commitBatch(CommitBatchInfo memory newBatchData, Storage.StoredBatchInfo memory lastStoredBatch) external;

  /// @notice Execute on chain operations in a verified batch
  /// @param batches Array of batches that contains the on chain operations to be executed
  /// @param onChainOperationsPubData Array of on chain operations that are verified and to be executed
  function executeBatches(Storage.StoredBatchInfo[] memory batches, bytes[] memory onChainOperationsPubData) external;

  /// @notice Verify a committed batch alongside its validity proof
  /// @param batch Batch to be verified
  /// @param proof Proof for the batch
  function verifyBatch(Storage.StoredBatchInfo memory batch, bytes memory proof) external;

  /// @notice Change the state root
  /// @param _lastStoredBatch Last committed batch
  /// @param _stateRoot New state root
  /// @param _validiumRoot New validium root
  /// @param proof Proof for the state root change
  function updateStateRoot(
    Storage.StoredBatchInfo calldata _lastStoredBatch,
    bytes32 _stateRoot,
    bytes32 _validiumRoot,
    bytes calldata proof
  ) external;

  /// @notice Change the treasury address
  /// @notice Can be called only by ZkLighter governor
  /// @param _newTreasury Address of the new treasury
  function setTreasury(address _newTreasury) external;

  /// @notice Change the insurance fund operator address
  /// @notice Can be called only by ZkLighter governor
  /// @param _newInsuranceFundOperator Address of the new insurance fund operator
  function setInsuranceFundOperator(address _newInsuranceFundOperator) external;
}

/// @dev Public storage getters of ZkLighter that L1CoreMessaging reads.
/// Kept off IZkLighter because ZkLighter inherits their public-variable getters
/// from Storage and ExtendableStorage.
interface IZkLighterPublic is IZkLighter {
  function treasury() external view returns (address);

  function insuranceFundOperator() external view returns (address);

  function addressToAccountIndex(address account) external view returns (uint48);

  function assetConfigs(
    uint16 assetIndex
  )
    external
    view
    returns (
      address tokenAddress,
      uint8 withdrawalsEnabled,
      uint56 extensionMultiplier,
      uint128 tickSize,
      uint64 depositCapTicks,
      uint64 minDepositTicks
    );
}
