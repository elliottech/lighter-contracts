// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IZkLighter.sol";
import "./interfaces/IZkLighterVerifier.sol";
import "./interfaces/IDesertVerifier.sol";
import "./lib/Bytes.sol";
import "./lib/TxTypes.sol";
import "./Storage.sol";
import "./ExtendableStorage.sol";

/// @title zkLighter Contract
/// @author zkLighter Team
contract ZkLighter is IZkLighter, Storage, ReentrancyGuardUpgradeable, ExtendableStorage {
  address private immutable zklighterImplementation;

  // OpenZeppelin Contracts (last updated v4.9.0) (proxy/utils/Initializable.sol)
  // * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure */
  // * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity. */
  // * Avoid leaving a contract uninitialized. */
  // * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation */
  // * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke */
  // * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed: */
  constructor() {
    zklighterImplementation = address(this);
    _disableInitializers();
  }

  /// @notice ZkLighter contract initialization.
  /// @param initializationParameters Encoded representation of initialization parameters:
  /// @dev _governanceAddress The address of Governance contract
  /// @dev _verifierAddress The address of Verifier contract
  /// @dev _additionalZkLighter The address of Additional zkLighter contract
  /// @dev _desertVerifier The address of Desert Verifier contract
  /// @dev _genesisStateRoot Genesis blocks (first block) state tree root hash
  /// @dev _genesisValidiumRoot Genesis blocks (first block) validium tree root hash
  function initialize(bytes calldata initializationParameters) external initializer {
    if (address(this) == zklighterImplementation) {
      revert ZkLighter_CannotBeInitialisedByImpl();
    }

    __ReentrancyGuard_init();

    (
      address _governanceAddress,
      address _verifierAddress,
      address _additionalZkLighter,
      address _desertVerifier,
      bytes32 _genesisStateRoot,
      bytes32 _genesisValidiumRoot
    ) = abi.decode(initializationParameters, (address, address, address, address, bytes32, bytes32));

    if (!_hasCode(_governanceAddress) || !_hasCode(_verifierAddress) || !_hasCode(_additionalZkLighter) || !_hasCode(_desertVerifier)) {
      revert ZkLighter_InvalidInitializeParameters();
    }

    verifier = IZkLighterVerifier(_verifierAddress);
    governance = IGovernance(_governanceAddress);
    additionalZkLighter = AdditionalZkLighter(_additionalZkLighter);
    desertVerifier = IDesertVerifier(_desertVerifier);

    StoredBatchInfo memory genesisBatchInfo = StoredBatchInfo({
      batchNumber: 0,
      endBlockNumber: 0,
      batchSize: 0,
      startTimestamp: 0,
      endTimestamp: 0,
      priorityRequestCount: 0,
      prefixPriorityRequestHash: 0,
      onChainOperationsHash: 0,
      stateRoot: _genesisStateRoot,
      validiumRoot: _genesisValidiumRoot,
      commitment: bytes32(0)
    });
    stateRoot = _genesisStateRoot;
    storedBatchHashes[0] = hashStoredBatchInfo(genesisBatchInfo);

    lastAccountIndex = 2; // First 3 accounts are reserved for system accounts
  }

  /// @notice ZkLighter contract upgrade. Can be external because Proxy contract intercepts illegal calls of this function
  /// @param upgradeParameters Encoded representation of upgrade parameters
  function upgrade(bytes calldata upgradeParameters) external nonReentrant {
    if (address(this) == zklighterImplementation) {
      revert ZkLighter_OnlyProxyCanCallUpgrade();
    }

    // Commit to the initialization parameters to ensure parameters are known at the time of upgrade initialization
    bytes32 upgradeParametersHash = keccak256(upgradeParameters);
    // Commits to 0 address for _additionalZkLighter, _desertVerifier and _stateRootUpgradeVerifier
    bytes32 initializationParametersCommitment = 0x46700b4d40ac5c35af2c22dda2787a91eb567b06c924a8fb8ae9a05b20c08c21;
    if (upgradeParametersHash != initializationParametersCommitment) {
      revert ZkLighter_InvalidUpgradeParameters();
    }

    (address _additionalZkLighter, address _desertVerifier, address _stateRootUpgradeVerifier) = abi.decode(
      upgradeParameters,
      (address, address, address)
    );

    if (_additionalZkLighter != address(0)) {
      if (!_hasCode(_additionalZkLighter)) {
        revert ZkLighter_InvalidUpgradeParameters();
      }
      additionalZkLighter = AdditionalZkLighter(_additionalZkLighter);
    }

    if (_desertVerifier != address(0)) {
      if (!_hasCode(_desertVerifier)) {
        revert ZkLighter_InvalidUpgradeParameters();
      }
      desertVerifier = IDesertVerifier(_desertVerifier);
    }

    if (_stateRootUpgradeVerifier != address(0)) {
      if (!_hasCode(_stateRootUpgradeVerifier)) {
        revert ZkLighter_InvalidUpgradeParameters();
      }
      stateRootUpgradeVerifier = IZkLighterStateRootUpgradeVerifier(_stateRootUpgradeVerifier);
    }
  }

  /// @inheritdoc IZkLighter
  function deposit(uint64 _amount, address _to) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function depositBatch(uint64[] calldata _amounts, address[] calldata _to, uint48[] calldata _accountIndex) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function changePubKey(uint48 _accountIndex, uint8 _apiKeyIndex, bytes calldata _pubKey) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function createMarket(uint8 _size_decimals, uint8 _price_decimals, bytes32 _symbol, TxTypes.CreateMarket calldata _params) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function updateMarket(TxTypes.UpdateMarket calldata _params) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function cancelAllOrders(uint48 _accountIndex) public {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function withdraw(uint48 _accountIndex, uint64 _usdcAmount) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function createOrder(uint48 _accountIndex, uint8 _marketIndex, uint48 _baseAmount, uint32 _price, uint8 _isAsk, uint8 _orderType) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function burnShares(uint48 _accountIndex, uint48 _publicPoolIndex, uint64 _shareAmount) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function revertBatches(StoredBatchInfo[] memory _batchesToRevert, StoredBatchInfo memory _remainingBatch) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function updateStateRoot(StoredBatchInfo calldata _lastStoredBatch, bytes32 _stateRoot, bytes32 _validiumRoot, bytes calldata proof) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function performDesert(uint48 _accountIndex, uint48 _masterAccountIndex, uint128 _totalAccountValue, bytes calldata proof) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function cancelOutstandingDepositsForDesertMode(uint64 _n, bytes[] memory _depositsPubData) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function commitBatch(CommitBatchInfo calldata newBatchData, StoredBatchInfo calldata lastStoredBatch) external nonReentrant onlyActive {
    governance.isActiveValidator(msg.sender);

    if (newBatchData.pubdataCommitments.length == 0) {
      revert ZkLighter_InvalidBlobCommitmentParams();
    }
    uint8 pubDataMode = uint8(bytes1(newBatchData.pubdataCommitments[0]));
    if (pubDataMode != uint8(PubDataMode.Blob)) {
      revert ZkLighter_InvalidPubDataMode();
    }
    if (newBatchData.endBlockNumber <= lastStoredBatch.endBlockNumber) {
      revert ZkLighter_NonIncreasingBlockNumber();
    }
    if (newBatchData.endBlockNumber != lastStoredBatch.endBlockNumber + newBatchData.batchSize) {
      revert ZkLighter_InvalidBatchSize();
    }
    if (newBatchData.startTimestamp < lastStoredBatch.endTimestamp || newBatchData.endTimestamp < newBatchData.startTimestamp) {
      revert ZkLighter_NonIncreasingTimestamp();
    }
    if (storedBatchHashes[committedBatchesCount] != hashStoredBatchInfo(lastStoredBatch)) {
      revert ZkLighter_StoredBatchInfoMismatch();
    }
    uint64 lastPriorityRequestToCommitCount = committedPriorityRequestCount + newBatchData.priorityRequestCount;
    if (executedPriorityRequestCount + openPriorityRequestCount < lastPriorityRequestToCommitCount) {
      revert ZkLighter_CommitBatchPriorityRequestCountMismatch();
    }
    if (
      lastPriorityRequestToCommitCount >= 1 &&
      priorityRequests[lastPriorityRequestToCommitCount - 1].prefixHash != newBatchData.prefixPriorityRequestHash
    ) {
      revert ZkLighter_PriorityRequestPrefixHashMismatch();
    }

    bytes32 aggregatedBlobCommitment = _processBlobs(newBatchData.pubdataCommitments[1:]);

    bytes32 oldStateRoot = lastStoredBatch.stateRoot;
    if (stateRootUpdates[committedBatchesCount] != bytes32(0)) {
      oldStateRoot = stateRootUpdates[committedBatchesCount];
    }

    committedBatchesCount++;
    if (newBatchData.onChainOperationsHash != bytes32(0)) {
      onChainExecutionQueue[executedOnChainBatchesCount + pendingOnChainBatchesCount] = ExecutionQueueItem({
        batchNumber: committedBatchesCount,
        totalPriorityRequests: committedPriorityRequestCount + newBatchData.priorityRequestCount
      });
      pendingOnChainBatchesCount++;
    }

    bytes32 commitment = keccak256(
      abi.encodePacked(
        newBatchData.endBlockNumber,
        newBatchData.batchSize,
        newBatchData.startTimestamp,
        newBatchData.endTimestamp,
        oldStateRoot,
        newBatchData.newStateRoot,
        newBatchData.newValidiumRoot,
        newBatchData.onChainOperationsHash,
        newBatchData.priorityRequestCount,
        newBatchData.prefixPriorityRequestHash,
        aggregatedBlobCommitment
      )
    );
    storedBatchHashes[committedBatchesCount] = hashStoredBatchInfo(
      StoredBatchInfo({
        batchNumber: committedBatchesCount,
        endBlockNumber: newBatchData.endBlockNumber,
        batchSize: newBatchData.batchSize,
        startTimestamp: newBatchData.startTimestamp,
        endTimestamp: newBatchData.endTimestamp,
        priorityRequestCount: newBatchData.priorityRequestCount,
        prefixPriorityRequestHash: newBatchData.prefixPriorityRequestHash,
        onChainOperationsHash: newBatchData.onChainOperationsHash,
        stateRoot: newBatchData.newStateRoot,
        validiumRoot: newBatchData.newValidiumRoot,
        commitment: commitment
      })
    );
    committedPriorityRequestCount += newBatchData.priorityRequestCount;
    emit BatchCommit(committedBatchesCount, newBatchData.batchSize, newBatchData.endBlockNumber);
  }

  /// @inheritdoc IZkLighter
  function verifyBatch(StoredBatchInfo memory batch, bytes calldata proof) external nonReentrant onlyActive {
    governance.isActiveValidator(msg.sender);

    if (batch.batchNumber != verifiedBatchesCount + 1) {
      revert ZkLighter_VerifyBatchNotInOrder();
    }
    if (hashStoredBatchInfo(batch) != storedBatchHashes[batch.batchNumber]) {
      revert ZkLighter_CannotVerifyNonCommittedBatch();
    }

    uint256[] memory inputs = new uint256[](1);
    inputs[0] = uint256(batch.commitment) % BN254_MODULUS;
    bool success = verifier.Verify(proof, inputs);
    if (!success) {
      revert ZkLighter_VerifyBatchProofFailed();
    }

    emit BatchVerification(batch.batchNumber, batch.batchSize, batch.endBlockNumber);

    verifiedBatchesCount++;
    verifiedPriorityRequestCount += batch.priorityRequestCount;
    lastVerifiedStateRoot = batch.stateRoot;
    lastVerifiedValidiumRoot = batch.validiumRoot;
    lastVerifiedEndBlockNumber = batch.endBlockNumber;
    // Lazy update the executed batches count when:
    // 1. There are no pending items in onChainExecutionQueue and a new batch is verified
    // 2. The next batch in the onChainExecutionQueue is greater than the verifiedBatchesCount
    if (pendingOnChainBatchesCount == 0 || onChainExecutionQueue[executedOnChainBatchesCount].batchNumber > verifiedBatchesCount) {
      executedBatchesCount = verifiedBatchesCount;
      stateRoot = batch.stateRoot;
      validiumRoot = batch.validiumRoot;
      openPriorityRequestCount -= verifiedPriorityRequestCount - executedPriorityRequestCount;
      executedPriorityRequestCount = verifiedPriorityRequestCount;
      emit BatchesExecuted(executedBatchesCount, batch.endBlockNumber);
    }
  }

  function _executeOneBatch(StoredBatchInfo memory batch, bytes memory _onChainOperationsPubData) internal {
    if (storedBatchHashes[batch.batchNumber] != hashStoredBatchInfo(batch)) {
      revert ZkLighter_StoredBatchInfoMismatch();
    }
    if (_onChainOperationsPubData.length % TxTypes.WithdrawLogSize != 0) {
      revert ZkLighter_InvalidPubDataLength();
    }
    bytes32 onChainPubDataHash = bytes32(0);
    for (uint256 i = 0; i < _onChainOperationsPubData.length; ) {
      uint8 logType;
      (, logType) = Bytes.readUInt8(_onChainOperationsPubData, i);
      if (logType != uint8(TxTypes.OnChainPubDataType.Withdraw)) {
        revert ZkLighter_InvalidPubDataType();
      }
      (TxTypes.Withdraw memory _tx, uint256 _offset) = TxTypes.readWithdrawOnChainLog(_onChainOperationsPubData, i);
      increaseBalanceToWithdraw(_tx.masterAccountIndex, _tx.usdcAmount);
      i = _offset;
      onChainPubDataHash = keccak256(
        abi.encodePacked(onChainPubDataHash, TxTypes.OnChainPubDataType.Withdraw, _tx.masterAccountIndex, _tx.usdcAmount)
      );
    }
    if (onChainPubDataHash != batch.onChainOperationsHash) {
      revert ZkLighter_OnChainOperationsHashMismatch();
    }
  }

  function executeBatches(StoredBatchInfo[] memory batches, bytes[] memory onChainOperationsPubData) external nonReentrant onlyActive {
    if (batches.length != onChainOperationsPubData.length) {
      revert ZkLighter_ExecuteInputLengthMismatch();
    }
    if (batches.length > pendingOnChainBatchesCount) {
      revert ZkLighter_ExecuteInputLengthGreaterThanPendingCount();
    }
    for (uint256 i = 0; i < batches.length; ++i) {
      uint64 batchNumber = batches[i].batchNumber;
      if (batchNumber > verifiedBatchesCount) {
        revert ZkLighter_CannotExecuteNonVerifiedBatch();
      }
      if (batchNumber != onChainExecutionQueue[executedOnChainBatchesCount].batchNumber) {
        revert ZkLighter_BatchNotInOnChainQueue();
      }
      _executeOneBatch(batches[i], onChainOperationsPubData[i]);
      uint64 numExecutedPriorityRequests = onChainExecutionQueue[executedOnChainBatchesCount].totalPriorityRequests - executedPriorityRequestCount;
      executedPriorityRequestCount = onChainExecutionQueue[executedOnChainBatchesCount].totalPriorityRequests;
      executedBatchesCount = batchNumber;
      executedOnChainBatchesCount++;
      pendingOnChainBatchesCount--;
      openPriorityRequestCount -= numExecutedPriorityRequests;
    }
    stateRoot = batches[batches.length - 1].stateRoot;
    validiumRoot = batches[batches.length - 1].validiumRoot;
    // Lazy update the executed batches count when:
    // 1. There are no pending items in onChainExecutionQueue and a new batch is verified
    // 2. The next batch in the onChainExecutionQueue is greater than the verifiedBatchesCount
    if (pendingOnChainBatchesCount == 0 || onChainExecutionQueue[executedOnChainBatchesCount].batchNumber > verifiedBatchesCount) {
      executedBatchesCount = verifiedBatchesCount;
      stateRoot = lastVerifiedStateRoot;
      validiumRoot = lastVerifiedValidiumRoot;
      openPriorityRequestCount -= verifiedPriorityRequestCount - executedPriorityRequestCount;
      executedPriorityRequestCount = verifiedPriorityRequestCount;
      emit BatchesExecuted(executedBatchesCount, lastVerifiedEndBlockNumber);
    } else {
      emit BatchesExecuted(executedBatchesCount, batches[batches.length - 1].endBlockNumber);
    }
  }

  /// @inheritdoc IZkLighter
  function transferERC20(IERC20 _token, address _to, uint128 _amount, uint128 _maxAmount) external returns (uint128 withdrawnAmount) {
    // Can be called only from this contract as one "external" call (to revert all this function state changes if it is needed)
    if (msg.sender != address(this)) {
      revert ZkLighter_OnlyZkLighter();
    }
    uint256 balanceBefore = _token.balanceOf(address(this));
    SafeERC20.safeTransfer(_token, _to, _amount);
    uint256 balanceAfter = _token.balanceOf(address(this));
    uint256 balanceDiff = balanceBefore - balanceAfter;
    if (balanceDiff > _maxAmount) {
      revert ZkLighter_RollUpBalanceBiggerThanMaxAmount();
    }
    return SafeCast.toUint128(balanceDiff);
  }

  function increaseBalanceToWithdraw(uint48 _masterAccountIndex, uint128 _amount) internal {
    uint128 balance = pendingBalance[_masterAccountIndex].balanceToWithdraw;
    pendingBalance[_masterAccountIndex] = PendingBalance(balance + _amount, FILLED_GAS_RESERVE_VALUE);
  }

  /// @inheritdoc IZkLighter
  function getPendingBalance(address _owner) public view returns (uint128) {
    uint48 _masterAccountIndex = getAccountIndexFromAddress(_owner);
    return pendingBalance[_masterAccountIndex].balanceToWithdraw;
  }

  /// @inheritdoc IZkLighter
  function withdrawPendingBalance(address _owner, uint128 _amount) external nonReentrant {
    uint48 masterAccountIndex = getAccountIndexFromAddress(_owner);
    uint128 balance = pendingBalance[masterAccountIndex].balanceToWithdraw;
    if (_amount > balance || _amount == 0) {
      revert ZkLighter_InvalidWithdrawAmount();
    }
    // We will allow withdrawals of `value` such that:
    // `value` <= user pending balance
    // `value` can be bigger then `_amount` requested if token takes fee from sender in addition to `_amount` requested
    uint128 amount = this.transferERC20(governance.usdc(), _owner, _amount, balance);
    // Update balanceToWithdraw by subtracting the actual amount that was sent
    pendingBalance[masterAccountIndex].balanceToWithdraw = balance - amount;
    emit WithdrawPending(_owner, amount);
  }

  /// @inheritdoc IZkLighter
  function activateDesertMode() external nonReentrant returns (bool) {
    bool trigger = openPriorityRequestCount != 0 &&
      block.timestamp >= priorityRequests[executedPriorityRequestCount].expirationTimestamp &&
      priorityRequests[executedPriorityRequestCount].expirationTimestamp != 0;
    if (trigger) {
      if (!desertMode) {
        desertMode = true;
        emit DesertMode();
      }
      return true;
    } else {
      return false;
    }
  }

  /// @notice Change address that collects fees from listed markets
  function setTreasury(address _newTreasury) external nonReentrant {
    governance.requireGovernor(msg.sender);
    if (_newTreasury == address(0)) {
      revert ZkLighter_TreasuryCannotBeZero();
    }
    if (getAccountIndexFromAddress(_newTreasury) != NIL_ACCOUNT_INDEX) {
      revert ZkLighter_TreasuryCannotBeInUse();
    }
    treasury = _newTreasury;
    emit TreasuryUpdate(treasury);
  }

  /// @notice Change address that operates the insurance fund
  function setInsuranceFundOperator(address _newInsuranceFundOperator) external nonReentrant {
    governance.requireGovernor(msg.sender);
    if (_newInsuranceFundOperator == address(0)) {
      revert ZkLighter_InsuranceFundOperatorCannotBeZero();
    }
    if (getAccountIndexFromAddress(_newInsuranceFundOperator) != NIL_ACCOUNT_INDEX) {
      revert ZkLighter_InsuranceFundOperatorCannotBeInUse();
    }
    insuranceFundOperator = _newInsuranceFundOperator;
    emit InsuranceFundOperatorUpdate(insuranceFundOperator);
  }

  /// @notice Delegates the call to the additional part of the main contract.
  /// @notice Should be only use to delegate the external calls as it passes the calldata
  /// @notice All functions delegated to additional contract should NOT be nonReentrant
  function delegateAdditional() internal {
    if (address(this) == zklighterImplementation) {
      revert ZkLighter_ImplCantDelegateToAddl();
    }

    address _target = address(additionalZkLighter);
    assembly {
      // The pointer to the free memory slot
      let ptr := mload(0x40)
      // Copy function signature and arguments from calldata at zero position into memory at pointer position
      calldatacopy(ptr, 0x0, calldatasize())
      // Delegatecall method of the implementation contract, returns 0 on error
      let result := delegatecall(gas(), _target, ptr, calldatasize(), 0x0, 0)
      // Get the size of the last return data
      let size := returndatasize()
      // Copy the size length of bytes from return data at zero position to pointer position
      returndatacopy(ptr, 0x0, size)

      // Depending on result value
      switch result
      case 0 {
        // End execution and revert state changes
        revert(ptr, size)
      }
      default {
        // Return data with length of size at pointers position
        return(ptr, size)
      }
    }
  }

  /// @notice Calls the point evaluation precompile to verify the blob commitment
  /// @param blobVersionedHash is the versioned hash of the blob
  /// @param evaluationPointCommitmentProof is the evaluation point commitment proof
  function _pointEvaluationPrecompile(bytes32 blobVersionedHash, bytes calldata evaluationPointCommitmentProof) internal view {
    bytes memory precompileInput = abi.encodePacked(blobVersionedHash, evaluationPointCommitmentProof);

    (bool success, bytes memory data) = POINT_EVALUATION_PRECOMPILE_ADDRESS.staticcall(precompileInput);

    // We verify that the point evaluation precompile call was successful by testing the latter 32 bytes of the
    // response is equal to BLS_MODULUS as defined in https://eips.ethereum.org/EIPS/eip-4844#point-evaluation-precompile
    if (!success) {
      revert ZkLighter_InvalidPointEvaluationParams();
    }
    (, uint256 result) = abi.decode(data, (uint256, uint256));
    if (result != BLS_MODULUS) {
      revert ZkLighter_InvalidPointEvaluationParams();
    }
  }

  /// @notice Verifies if the sent blob commitment data is consistent with the blob itself
  /// @param pubDataCommitments is a list of: evaluationPointX (32 bytes) || evaluationPointY (32 bytes) || commitment (48 bytes) || proof (48 bytes)) = 160 bytes
  /// @return aggregatedBlobCommitment is the aggregated blob commitment for all blobs in the pubDataCommitments
  function _processBlobs(bytes calldata pubDataCommitments) internal view returns (bytes32 aggregatedBlobCommitment) {
    if (pubDataCommitments.length % BLOB_DATA_COMMITMENT_BYTE_SIZE != 0) {
      revert ZkLighter_InvalidBlobCommitmentParams();
    }

    uint256 blobCount = pubDataCommitments.length / BLOB_DATA_COMMITMENT_BYTE_SIZE;
    if (blobCount > MAX_BLOB_COUNT) {
      revert ZkLighter_InvalidBlobCount(blobCount);
    }

    for (uint256 i = 0; i < blobCount; i++) {
      bytes calldata _blobDataCommitment = pubDataCommitments[i * BLOB_DATA_COMMITMENT_BYTE_SIZE:(1 + i) * BLOB_DATA_COMMITMENT_BYTE_SIZE];
      bytes32 evaluationPointX = bytes32(_blobDataCommitment[0:32]);
      bytes32 evaluationPointY = bytes32(_blobDataCommitment[32:64]);
      bytes32 blobVersionedHash;
      assembly {
        blobVersionedHash := blobhash(i)
      }
      if (blobVersionedHash == bytes32(0)) {
        revert ZkLighter_InvalidBlobCommitmentParams();
      }

      _pointEvaluationPrecompile(blobVersionedHash, _blobDataCommitment);

      bytes32 currentBlobCommitment = keccak256(abi.encodePacked(evaluationPointX, evaluationPointY, blobVersionedHash));
      if (i == 0) {
        aggregatedBlobCommitment = currentBlobCommitment;
      } else {
        aggregatedBlobCommitment = keccak256(abi.encodePacked(aggregatedBlobCommitment, currentBlobCommitment));
      }
    }

    // Verify there are no extra blob hashes attached to the call. `blobhash` will return 0 bytes if no blob
    // hash is present at given index. Leaps are not allowed, so checking the first next index is sufficient.
    bytes32 emptyBlobVersionedHash;
    assembly {
      emptyBlobVersionedHash := blobhash(blobCount)
    }
    if (emptyBlobVersionedHash != bytes32(0)) {
      revert ZkLighter_InvalidBlobCommitmentParams();
    }

    return aggregatedBlobCommitment;
  }
}
