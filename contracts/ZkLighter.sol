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

    _registerDefaultAssetConfigs();

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
    bytes32 initializationParametersCommitment = 0xde9fd00f43743441cc54f7bbe8192fdf645afb63d5bee35c2294921122d560e6;
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

  function _registerDefaultAssetConfigs() internal {
    address ethAddress = address(0);
    uint56 ethExtensionMultiplier = 100;
    uint128 ethTickSize = 10 ** 10; // 0.00000001 ETH
    assetConfigs[NATIVE_ASSET_INDEX] = AssetConfig({
      tokenAddress: ethAddress,
      withdrawalsEnabled: 1,
      extensionMultiplier: ethExtensionMultiplier,
      tickSize: ethTickSize,
      depositCapTicks: MAX_DEPOSIT_CAP_TICKS,
      minDepositTicks: 100_000 // 0.001 ETH
    });
    tokenToAssetIndex[ethAddress] = NATIVE_ASSET_INDEX;
    emit RegisterAssetConfig(NATIVE_ASSET_INDEX, ethAddress, 1, ethExtensionMultiplier, ethTickSize, MAX_DEPOSIT_CAP_TICKS, 100_000);

    address usdcAddress = address(governance.usdc());
    uint56 usdcExtensionMultiplier = 1_000_000;
    uint128 usdcTickSize = 1;
    assetConfigs[USDC_ASSET_INDEX] = AssetConfig({
      tokenAddress: usdcAddress,
      withdrawalsEnabled: 1,
      extensionMultiplier: usdcExtensionMultiplier,
      tickSize: usdcTickSize,
      depositCapTicks: MAX_DEPOSIT_CAP_TICKS,
      minDepositTicks: 1_000_000 // 1 USDC
    });
    tokenToAssetIndex[usdcAddress] = USDC_ASSET_INDEX;
    emit RegisterAssetConfig(USDC_ASSET_INDEX, usdcAddress, 1, usdcExtensionMultiplier, usdcTickSize, MAX_DEPOSIT_CAP_TICKS, 1_000_000);
  }

  /// @inheritdoc IZkLighter
  function registerAssetConfig(
    uint16 assetIndex,
    address tokenAddress,
    uint8 withdrawalsEnabled,
    uint56 extensionMultiplier,
    uint128 tickSize,
    uint64 depositCapTicks,
    uint64 minDepositTicks
  ) external nonReentrant onlyActive {
    governance.requireGovernor(msg.sender);

    if (assetIndex == NATIVE_ASSET_INDEX || assetConfigs[assetIndex].tokenAddress != address(0)) {
      revert ZkLighter_InvalidAssetIndex();
    }
    if (assetIndex < MIN_ASSET_INDEX || assetIndex > MAX_ASSET_INDEX) {
      revert ZkLighter_InvalidAssetIndex();
    }
    if (tokenAddress == address(0) || tokenToAssetIndex[tokenAddress] != 0) {
      revert ZkLighter_InvalidAssetConfigParams();
    }

    if (withdrawalsEnabled != 0 && withdrawalsEnabled != 1) {
      revert ZkLighter_InvalidAssetConfigParams();
    }

    if (!_hasCode(tokenAddress)) {
      revert ZkLighter_InvalidAssetConfigParams();
    }

    if (tickSize == 0 || depositCapTicks == 0 || minDepositTicks == 0) {
      revert ZkLighter_InvalidAssetConfigParams();
    }

    if (tickSize > MAX_TICK_SIZE || depositCapTicks > MAX_DEPOSIT_CAP_TICKS || minDepositTicks > depositCapTicks) {
      revert ZkLighter_InvalidAssetConfigParams();
    }

    uint128 extendedDepositCapTicks = uint128(extensionMultiplier) * uint128(depositCapTicks);
    if (
      extensionMultiplier == 0 || extensionMultiplier > MAX_ASSET_EXTENSION_MULTIPLIER || extendedDepositCapTicks > MAX_EXTENDED_DEPOSIT_CAP_TICKS
    ) {
      revert ZkLighter_InvalidAssetConfigParams();
    }

    assetConfigs[assetIndex] = AssetConfig({
      tokenAddress: tokenAddress,
      withdrawalsEnabled: withdrawalsEnabled,
      extensionMultiplier: extensionMultiplier,
      tickSize: tickSize,
      depositCapTicks: depositCapTicks,
      minDepositTicks: minDepositTicks
    });
    tokenToAssetIndex[tokenAddress] = assetIndex;
    emit RegisterAssetConfig(assetIndex, tokenAddress, withdrawalsEnabled, extensionMultiplier, tickSize, depositCapTicks, minDepositTicks);
  }

  /// @inheritdoc IZkLighter
  function updateAssetConfig(
    uint16 assetIndex,
    uint8 withdrawalsEnabled,
    uint64 depositCapTicks,
    uint64 minDepositTicks
  ) external nonReentrant onlyActive {
    governance.requireGovernor(msg.sender);

    AssetConfig memory config = assetConfigs[assetIndex];
    if (assetIndex != NATIVE_ASSET_INDEX && config.tokenAddress == address(0)) {
      revert ZkLighter_InvalidAssetIndex();
    }

    if (withdrawalsEnabled != 0 && withdrawalsEnabled != 1) {
      revert ZkLighter_InvalidAssetConfigParams();
    }

    // Withdrawals can not be disabled if they are enabled already
    // Only transition allowed for this parameter is from disabled to enabled
    if (withdrawalsEnabled == 0 && config.withdrawalsEnabled == 1) {
      revert ZkLighter_InvalidAssetConfigParams();
    }

    if (depositCapTicks == 0 || minDepositTicks == 0) {
      revert ZkLighter_InvalidAssetConfigParams();
    }

    if (depositCapTicks > MAX_DEPOSIT_CAP_TICKS || minDepositTicks > depositCapTicks) {
      revert ZkLighter_InvalidAssetConfigParams();
    }

    uint128 extendedDepositCapTicks = uint128(config.extensionMultiplier) * uint128(depositCapTicks);
    if (extendedDepositCapTicks > MAX_EXTENDED_DEPOSIT_CAP_TICKS) {
      revert ZkLighter_InvalidAssetConfigParams();
    }

    assetConfigs[assetIndex] = AssetConfig({
      tokenAddress: config.tokenAddress,
      withdrawalsEnabled: withdrawalsEnabled,
      extensionMultiplier: config.extensionMultiplier,
      tickSize: config.tickSize,
      depositCapTicks: depositCapTicks,
      minDepositTicks: minDepositTicks
    });
    emit UpdateAssetConfig(assetIndex, withdrawalsEnabled, depositCapTicks, minDepositTicks);
  }

  /// @inheritdoc IZkLighter
  function setSystemConfig(TxTypes.SetSystemConfig calldata _params) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function registerAsset(uint8 _l1Decimals, uint8 _decimals, bytes32 _symbol, TxTypes.RegisterAsset calldata _params) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function updateAsset(TxTypes.UpdateAsset calldata _params) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function deposit(address _to, uint16 _assetIndex, TxTypes.RouteType _routeType, uint256 _amount) external payable {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function depositBatch(uint64[] calldata _amount, address[] calldata _to, uint48[] calldata _accountIndex) external {
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
  function cancelAllOrders(uint48 _accountIndex) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function withdraw(uint48 _accountIndex, uint16 _assetIndex, TxTypes.RouteType _routeType, uint64 _baseAmount) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function createOrder(uint48 _accountIndex, uint16 _marketIndex, uint48 _baseAmount, uint32 _price, uint8 _isAsk, uint8 _orderType) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function burnShares(uint48 _accountIndex, uint48 _publicPoolIndex, uint64 _shareAmount) external {
    delegateAdditional();
  }

  /// @inheritdoc IZkLighter
  function updateStateRoot(StoredBatchInfo calldata _lastStoredBatch, bytes32 _stateRoot, bytes32 _validiumRoot, bytes calldata proof) external {
    delegateAdditional();
  }

  function createExitCommitment(
    uint256 stateRoot,
    uint48 _accountIndex,
    uint48 _masterAccountIndex,
    uint16 _assetIndex,
    uint128 _totalBaseAmount
  ) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(stateRoot, _accountIndex, _masterAccountIndex, _assetIndex, _totalBaseAmount));
  }

  /// @notice Performs exit from zkLighter in desert mode
  function performDesert(
    uint48 _accountIndex,
    uint48 _masterAccountIndex,
    uint16 _assetIndex,
    uint128 _totalBaseAmount,
    bytes calldata proof
  ) external nonReentrant {
    // Must be in desert mode
    if (!desertMode) {
      revert ZkLighter_DesertModeInactive();
    }

    if (accountPerformedDesertForAsset[_assetIndex][_accountIndex]) {
      revert ZkLighter_AccountAlreadyPerformedDesertForAsset();
    }

    uint256[] memory inputs = new uint256[](1);
    bytes32 commitment = createExitCommitment(uint256(stateRoot), _accountIndex, _masterAccountIndex, _assetIndex, _totalBaseAmount);
    inputs[0] = uint256(commitment) % BN254_MODULUS;
    bool success = desertVerifier.Verify(proof, inputs);
    if (!success) {
      revert ZkLighter_DesertVerifyProofFailed();
    }

    increaseBalanceToWithdraw(_masterAccountIndex, _assetIndex, _totalBaseAmount);
    accountPerformedDesertForAsset[_assetIndex][_accountIndex] = true;
  }

  /// @inheritdoc IZkLighter
  function cancelOutstandingDepositsForDesertMode(uint64 _n, bytes[] memory _priorityPubData) external nonReentrant {
    // Must be in desert mode
    if (!desertMode) {
      revert ZkLighter_DesertModeInactive();
    }

    if (openPriorityRequestCount == 0 || _n == 0) {
      revert ZkLighter_NoOutstandingDepositsForCancelation();
    }

    if (_n > openPriorityRequestCount || _n != _priorityPubData.length) {
      revert ZkLighter_InvalidParamsForCancelOutstandingDeposits();
    }

    uint64 startIndex = executedPriorityRequestCount;

    bytes32 pubDataPrefixHash = bytes32(0);
    if (executedPriorityRequestCount > 0) {
      pubDataPrefixHash = priorityRequests[executedPriorityRequestCount - 1].prefixHash;
    }

    uint64 currentPubDataIdx = 0;
    for (uint64 id = startIndex; id < startIndex + _n; ++id) {
      if (_priorityPubData[currentPubDataIdx].length > MAX_PRIORITY_REQUEST_PUBDATA_SIZE || _priorityPubData[currentPubDataIdx].length == 0) {
        revert ZkLighter_InvalidParamsForCancelOutstandingDeposits();
      }

      bytes memory paddedPubData = new bytes(MAX_PRIORITY_REQUEST_PUBDATA_SIZE);
      for (uint256 i = 0; i < _priorityPubData[currentPubDataIdx].length; ++i) {
        paddedPubData[i] = _priorityPubData[currentPubDataIdx][i];
      }

      pubDataPrefixHash = keccak256(abi.encodePacked(pubDataPrefixHash, paddedPubData));
      if (pubDataPrefixHash != priorityRequests[id].prefixHash) {
        revert ZkLighter_DepositPubdataHashMismatch();
      }

      if (uint8(_priorityPubData[currentPubDataIdx][0]) == TxTypes.PriorityPubDataTypeL1Deposit) {
        if (_priorityPubData[currentPubDataIdx].length != TxTypes.DEPOSIT_PUB_DATA_SIZE) {
          revert ZkLighter_DepositPubdataHashMismatch();
        }
        bytes memory depositPubdata = _priorityPubData[currentPubDataIdx];
        (uint48 accountIndex, uint16 assetIndex, uint64 baseAmount) = TxTypes.readDepositForDesertMode(depositPubdata);
        increaseBalanceToWithdraw(accountIndex, assetIndex, baseAmount);
      }

      ++currentPubDataIdx;
    }

    openPriorityRequestCount -= _n;
    executedPriorityRequestCount += _n;
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
    bytes32 onChainPubDataHash = bytes32(0);
    uint256 len = _onChainOperationsPubData.length;
    for (uint256 i = 0; i < len; ) {
      uint8 logType;
      (, logType) = Bytes.readUInt8(_onChainOperationsPubData, i);
      if (logType == uint8(TxTypes.OnChainPubDataType.Withdraw)) {
        if (len - i < TxTypes.WithdrawLogSize) {
          revert ZkLighter_InvalidPubDataLength();
        }
        (TxTypes.Withdraw memory _tx, uint256 _offset) = TxTypes.readWithdrawOnChainLog(_onChainOperationsPubData, i);
        increaseBalanceToWithdraw(_tx.masterAccountIndex, _tx.assetIndex, _tx.baseAmount);
        onChainPubDataHash = keccak256(
          abi.encodePacked(onChainPubDataHash, TxTypes.OnChainPubDataType.Withdraw, _tx.masterAccountIndex, _tx.assetIndex, _tx.baseAmount)
        );
        i = _offset;
      } else if (logType == uint8(TxTypes.OnChainPubDataType.USDCWithdraw)) {
        if (len - i < TxTypes.USDCWithdrawLogSize) {
          revert ZkLighter_InvalidPubDataLength();
        }
        (TxTypes.USDCWithdraw memory _tx, uint256 _offset) = TxTypes.readUSDCWithdrawOnChainLog(_onChainOperationsPubData, i);
        increaseBalanceToWithdraw(_tx.masterAccountIndex, USDC_ASSET_INDEX, _tx.usdcAmount);
        onChainPubDataHash = keccak256(
          abi.encodePacked(onChainPubDataHash, TxTypes.OnChainPubDataType.USDCWithdraw, _tx.masterAccountIndex, _tx.usdcAmount)
        );
        i = _offset;
      } else {
        revert ZkLighter_InvalidPubDataType();
      }
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
  function revertBatches(StoredBatchInfo[] memory _batchesToRevert, StoredBatchInfo memory _remainingBatch) external nonReentrant onlyActive {
    governance.isActiveValidator(msg.sender);

    for (uint32 i = 0; i < _batchesToRevert.length; ++i) {
      StoredBatchInfo memory storedBatchInfo = _batchesToRevert[i];
      if (storedBatchInfo.endBlockNumber == 0) {
        revert ZkLighter_CannotRevertGenesisBatch();
      }
      if (storedBatchHashes[committedBatchesCount] != hashStoredBatchInfo(storedBatchInfo)) {
        revert ZkLighter_StoredBatchInfoMismatch();
      }
      if (storedBatchInfo.batchNumber != committedBatchesCount) {
        revert ZkLighter_StoredBatchInfoMismatch();
      }
      delete storedBatchHashes[committedBatchesCount];
      if (storedBatchInfo.onChainOperationsHash != bytes32(0)) {
        if (pendingOnChainBatchesCount == 0) {
          revert ZkLighter_CannotRevertExecutedBatch();
        }
        uint64 totalOnChainBatchesCount = executedOnChainBatchesCount + pendingOnChainBatchesCount;
        if (onChainExecutionQueue[totalOnChainBatchesCount - 1].batchNumber != storedBatchInfo.batchNumber) {
          revert ZkLighter_StoredBatchInfoMismatch();
        }
        // Remove the batch from the execution queue
        delete onChainExecutionQueue[totalOnChainBatchesCount - 1];
        pendingOnChainBatchesCount--;
      }
      committedBatchesCount--;
      committedPriorityRequestCount -= storedBatchInfo.priorityRequestCount;
      if (storedBatchInfo.batchNumber <= verifiedBatchesCount) {
        verifiedBatchesCount--;
        verifiedPriorityRequestCount -= storedBatchInfo.priorityRequestCount;
      }
    }

    // Can not revert executed batch or priority requests
    if (committedBatchesCount < executedBatchesCount || committedPriorityRequestCount < executedPriorityRequestCount) {
      revert ZkLighter_CannotRevertExecutedBatch();
    }

    // Make sure the remaining batch is the last batch
    if (storedBatchHashes[committedBatchesCount] != hashStoredBatchInfo(_remainingBatch)) {
      revert ZkLighter_StoredBatchInfoMismatch();
    }
    // If we reverted verified batches, update the last verified variables for lazy update on executions
    if (_remainingBatch.batchNumber == verifiedBatchesCount) {
      lastVerifiedStateRoot = _remainingBatch.stateRoot;
      lastVerifiedValidiumRoot = _remainingBatch.validiumRoot;
      lastVerifiedEndBlockNumber = _remainingBatch.endBlockNumber;
    }
    emit BatchesRevert(committedBatchesCount);
  }

  /// @inheritdoc IZkLighter
  function transferERC20(IERC20 _token, address _to, uint256 _amount, uint256 _maxAmount) external returns (uint256) {
    // can be called only from this contract as one "external" call (to revert all this function state changes if it is needed)
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
    return balanceDiff;
  }

  /// @inheritdoc IZkLighter
  function transferETH(address _to, uint256 _amount) external returns (uint256) {
    // can be called only from this contract as one "external" call (to revert all this function state changes if it is needed)
    if (msg.sender != address(this)) {
      revert ZkLighter_OnlyZkLighter();
    }
    (bool success, ) = _to.call{value: _amount}("");
    if (!success) {
      revert ZkLighter_ETHTransferFailed();
    }
    return _amount;
  }

  function increaseBalanceToWithdraw(uint48 _masterAccountIndex, uint16 _assetIndex, uint128 _baseAmount) internal {
    uint128 balance = pendingAssetBalances[_assetIndex][_masterAccountIndex].balanceToWithdraw;
    pendingAssetBalances[_assetIndex][_masterAccountIndex] = PendingBalance(balance + _baseAmount, FILLED_GAS_RESERVE_VALUE);
  }

  /// @inheritdoc IZkLighter
  function getPendingBalance(address _owner, uint16 _assetIndex) external view returns (uint128) {
    uint48 _masterAccountIndex = getAccountIndexFromAddress(_owner);
    return pendingAssetBalances[_assetIndex][_masterAccountIndex].balanceToWithdraw;
  }

  function getPendingBalanceLegacy(address _owner) public view returns (uint128) {
    uint48 _masterAccountIndex = getAccountIndexFromAddress(_owner);
    return DEPRECATED_pendingBalance[_masterAccountIndex].balanceToWithdraw;
  }

  /// @inheritdoc IZkLighter
  function withdrawPendingBalance(address _owner, uint16 _assetIndex, uint128 _baseAmount) external nonReentrant {
    uint48 masterAccountIndex = getAccountIndexFromAddress(_owner);
    uint128 baseBalance = pendingAssetBalances[_assetIndex][masterAccountIndex].balanceToWithdraw;
    if (_baseAmount > baseBalance || _baseAmount == 0) {
      revert ZkLighter_InvalidWithdrawAmount();
    }

    AssetConfig memory assetConfig = assetConfigs[_assetIndex];
    if (_assetIndex != NATIVE_ASSET_INDEX && assetConfig.tokenAddress == address(0)) {
      revert ZkLighter_InvalidAssetIndex();
    }
    uint256 amount = uint256(_baseAmount) * uint256(assetConfig.tickSize);
    uint256 balance = uint256(baseBalance) * uint256(assetConfig.tickSize);
    // We will allow withdrawals of `value` such that:
    // `value` <= user pending balance
    // `value` can be bigger then `_amount` requested if token stakes fee from sender in addition to `_amount` requested
    uint256 transferredAmount;
    if (_assetIndex == NATIVE_ASSET_INDEX) {
      transferredAmount = this.transferETH(_owner, amount);
    } else {
      transferredAmount = this.transferERC20(IERC20(assetConfig.tokenAddress), _owner, amount, balance);
    }
    if (transferredAmount % assetConfig.tickSize != 0) {
      revert ZkLighter_TransferredAmountNotMultipleOfTickSize();
    }

    // update balanceToWithdraw by subtracting the actual amount that was sent
    uint256 transferredBaseAmount = transferredAmount / assetConfig.tickSize;
    uint128 transferredBaseAmount128 = SafeCast.toUint128(transferredBaseAmount);
    pendingAssetBalances[_assetIndex][masterAccountIndex].balanceToWithdraw = baseBalance - transferredBaseAmount128;
    emit WithdrawPending(_owner, _assetIndex, transferredBaseAmount128);
  }

  /// @inheritdoc IZkLighter
  function withdrawPendingBalanceLegacy(address _owner, uint128 _baseAmount) external nonReentrant {
    uint48 masterAccountIndex = getAccountIndexFromAddress(_owner);
    uint128 baseBalance = DEPRECATED_pendingBalance[masterAccountIndex].balanceToWithdraw;
    if (_baseAmount > baseBalance || _baseAmount == 0) {
      revert ZkLighter_InvalidWithdrawAmount();
    }
    // We will allow withdrawals of `value` such that:
    // `value` <= user pending balance
    // `value` can be bigger then `_amount` requested if token takes fee from sender in addition to `_amount` requested
    uint256 amount = this.transferERC20(governance.usdc(), _owner, uint256(_baseAmount), uint256(baseBalance));
    uint128 transferredBaseAmount128 = SafeCast.toUint128(amount);

    // Update balanceToWithdraw by subtracting the actual amount that was sent
    DEPRECATED_pendingBalance[masterAccountIndex].balanceToWithdraw = baseBalance - transferredBaseAmount128;
    emit WithdrawPending(_owner, USDC_ASSET_INDEX, transferredBaseAmount128);
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
