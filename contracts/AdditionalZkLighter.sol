// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IEvents.sol";
import "./lib/TxTypes.sol";
import "./Storage.sol";
import "./ExtendableStorage.sol";

/// @title zkLighter Additional Contract
/// @notice zkLighter Contract delegates some of its functionality to this contract
/// @author zkLighter Team
contract AdditionalZkLighter is IEvents, Storage, ReentrancyGuardUpgradeable, ExtendableStorage {
  error AdditionalZkLighter_StoredBatchHashMismatch();
  error AdditionalZkLighter_CannotRevertGenesisBatch();
  error AdditionalZkLighter_CannotRevertExecutedBatch();
  error AdditionalZkLighter_InvalidDepositAmount();
  error AdditionalZkLighter_InvalidWithdrawAmount();
  error AdditionalZkLighter_InvalidAccountIndex();
  error AdditionalZkLighter_InvalidDepositBatchLength();
  error AdditionalZkLighter_InvalidApiKeyIndex();
  error AdditionalZkLighter_InvalidPubKey();
  error AdditionalZkLighter_RecipientAddressInvalid();
  error AdditionalZkLighter_InvalidMarketDecimals();
  error AdditionalZkLighter_InvalidMarketIndex();
  error AdditionalZkLighter_InvalidMarketStatus();
  error AdditionalZkLighter_InvalidQuoteMultiplier();
  error AdditionalZkLighter_InvalidFeeAmount();
  error AdditionalZkLighter_InvalidMarginFraction();
  error AdditionalZkLighter_InvalidInterestRate();
  error AdditionalZkLighter_InvalidMinAmounts();
  error AdditionalZkLighter_InvalidShareAmount();
  error AdditionalZkLighter_MarketAlreadyExists();
  error AdditionalZkLighter_TooManyRegisteredAccounts();
  error AdditionalZkLighter_PubdataLengthMismatch();
  error AdditionalZkLighter_DesertModeInactive();
  error AdditionalZkLighter_DesertVerifyProofFailed();
  error AdditionalZkLighter_PendingVerifiedRequestExecution();
  error AdditionalZkLighter_InvalidDesertParameters();
  error AdditionalZkLighter_DesertPerformedForAccount();
  error AdditionalZkLighter_NoOutstandingDepositsForCancelation();
  error AdditionalZkLighter_InvalidParamsForCancelOutstandingDeposits();
  error AdditionalZkLighter_DepositPubdataHashMismatch();
  error AdditionalZkLighter_InvalidCreateOrderParameters();
  error AdditionalZkLighter_AccountIsNotRegistered();
  error AdditionalZkLighter_StoredBatchInfoMismatch();
  error AdditionalZkLighter_InvalidFundingClamps();
  error AdditionalZkLighter_InvalidOpenInterestLimit();
  error AdditionalZkLighter_InvalidOrderQuoteLimit();
  error AdditionalZkLighter_StateRootUpgradeVerifierFailed();
  error AdditionalZkLighter_StateRootUpgradeVerifierNotFound();

  /// @notice Reverts non-executed batches
  /// @param _batchesToRevert List of StoredBatchInfos to revert
  /// @param _remainingBatch Last batch that is not reverted
  function revertBatches(StoredBatchInfo[] memory _batchesToRevert, StoredBatchInfo memory _remainingBatch) external nonReentrant onlyActive {
    governance.isActiveValidator(msg.sender);

    for (uint32 i = 0; i < _batchesToRevert.length; ++i) {
      StoredBatchInfo memory storedBatchInfo = _batchesToRevert[i];
      if (storedBatchInfo.endBlockNumber == 0) {
        revert AdditionalZkLighter_CannotRevertGenesisBatch();
      }
      if (storedBatchHashes[committedBatchesCount] != hashStoredBatchInfo(storedBatchInfo)) {
        revert AdditionalZkLighter_StoredBatchHashMismatch();
      }
      if (storedBatchInfo.batchNumber != committedBatchesCount) {
        revert AdditionalZkLighter_StoredBatchInfoMismatch();
      }
      delete storedBatchHashes[committedBatchesCount];
      if (storedBatchInfo.onChainOperationsHash != bytes32(0)) {
        if (pendingOnChainBatchesCount == 0) {
          revert AdditionalZkLighter_CannotRevertExecutedBatch();
        }
        uint64 totalOnChainBatchesCount = executedOnChainBatchesCount + pendingOnChainBatchesCount;
        if (onChainExecutionQueue[totalOnChainBatchesCount - 1].batchNumber != storedBatchInfo.batchNumber) {
          revert AdditionalZkLighter_StoredBatchInfoMismatch();
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
      revert AdditionalZkLighter_CannotRevertExecutedBatch();
    }

    // Make sure the remaining batch is the last batch
    if (storedBatchHashes[committedBatchesCount] != hashStoredBatchInfo(_remainingBatch)) {
      revert AdditionalZkLighter_StoredBatchHashMismatch();
    }
    // If we reverted verified batches, update the last verified variables for lazy update on executions
    if (_remainingBatch.batchNumber == verifiedBatchesCount) {
      lastVerifiedStateRoot = _remainingBatch.stateRoot;
      lastVerifiedValidiumRoot = _remainingBatch.validiumRoot;
      lastVerifiedEndBlockNumber = _remainingBatch.endBlockNumber;
    }
    emit BatchesRevert(committedBatchesCount);
  }

  function updateStateRoot(
    StoredBatchInfo calldata _lastStoredBatch,
    bytes32 _stateRoot,
    bytes32 _validiumRoot,
    bytes calldata proof
  ) external nonReentrant onlyActive {
    governance.isActiveValidator(msg.sender);

    if (storedBatchHashes[committedBatchesCount] != hashStoredBatchInfo(_lastStoredBatch)) {
      revert AdditionalZkLighter_StoredBatchInfoMismatch();
    }

    if (executedBatchesCount != committedBatchesCount) {
      revert AdditionalZkLighter_PendingVerifiedRequestExecution();
    }

    if (stateRootUpgradeVerifier != IZkLighterStateRootUpgradeVerifier(address(0))) {
      bytes32 hashOutput = keccak256(abi.encodePacked(stateRoot, validiumRoot, _stateRoot, _validiumRoot));

      uint256[] memory inputs = new uint256[](1);
      inputs[0] = uint256(hashOutput) % BN254_MODULUS;

      bool success = stateRootUpgradeVerifier.Verify(proof, inputs);
      if (!success) {
        revert AdditionalZkLighter_StateRootUpgradeVerifierFailed();
      }

      stateRootUpgradeVerifier = IZkLighterStateRootUpgradeVerifier(address(0));
    } else {
      revert AdditionalZkLighter_StateRootUpgradeVerifierNotFound();
    }

    stateRoot = _stateRoot;
    validiumRoot = _validiumRoot;
    lastVerifiedStateRoot = _stateRoot;
    lastVerifiedValidiumRoot = _validiumRoot;
    stateRootUpdates[committedBatchesCount] = _stateRoot;

    emit StateRootUpdate(committedBatchesCount, _lastStoredBatch.stateRoot, _stateRoot);
  }

  function _deposit(uint64[] memory _amount, address[] memory _to) internal {
    IERC20 _token = governance.usdc();
    uint256 totalAmount = 0;
    for (uint256 i = 0; i < _amount.length; ++i) {
      totalAmount += _amount[i];
      if (_amount[i] < MIN_DEPOSIT_AMOUNT) {
        revert AdditionalZkLighter_InvalidDepositAmount();
      }
      if (_to[i] == address(0)) {
        revert AdditionalZkLighter_RecipientAddressInvalid();
      }
    }

    uint256 balanceBefore = _token.balanceOf(address(this));
    SafeERC20.safeTransferFrom(_token, msg.sender, address(this), totalAmount);

    // Token transfer failed deposit
    uint256 balanceAfter = _token.balanceOf(address(this));
    uint256 depositAmount = SafeCast.toUint128(balanceAfter - balanceBefore);
    if (depositAmount == 0 || depositAmount > MAX_DEPOSIT_AMOUNT || balanceAfter > MAX_EXCHANGE_USDC_AMOUNT || depositAmount < totalAmount) {
      revert AdditionalZkLighter_InvalidDepositAmount();
    }
    if (depositAmount > totalAmount) {
      increaseBalanceToWithdraw(TREASURY_ACCOUNT_INDEX, SafeCast.toUint128(depositAmount - totalAmount));
    }
    for (uint256 i = 0; i < _amount.length; ++i) {
      registerDeposit(_amount[i], _to[i]);
    }
  }

  /// @notice Deposit collateral (usdc) to zkLighter
  /// @param _amount usdc amount to deposit
  /// @param _to The receiver L1 address
  function deposit(uint64 _amount, address _to) external nonReentrant onlyActive {
    uint64[] memory amount = new uint64[](1);
    amount[0] = _amount;
    address[] memory to = new address[](1);
    to[0] = _to;
    _deposit(amount, to);
  }

  /// @notice Deposit USDC to Lighter for multiple users
  /// @param _amount Array of USDC Token amounts
  /// @param _to Array of receiver L1 addresses
  /// @param _accountIndex Array of account index values, will be used in the future
  function depositBatch(uint64[] calldata _amount, address[] calldata _to, uint48[] calldata _accountIndex) external nonReentrant onlyActive {
    if (_amount.length != _to.length || _amount.length != _accountIndex.length || _amount.length == 0 || _amount.length > MAX_BATCH_DEPOSIT_LENGTH) {
      revert AdditionalZkLighter_InvalidDepositBatchLength();
    }
    _deposit(_amount, _to);
  }

  /// @notice Change Lighter public key for an account api key slot
  function changePubKey(uint48 _accountIndex, uint8 _apiKeyIndex, bytes calldata _pubKey) external nonReentrant onlyActive {
    if (_accountIndex > MAX_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }
    if (_apiKeyIndex > MAX_API_KEY_INDEX) {
      revert AdditionalZkLighter_InvalidApiKeyIndex();
    }

    // Verify that the public key is of the correct length
    if (_pubKey.length != PUB_KEY_BYTES_SIZE) {
      revert AdditionalZkLighter_InvalidPubKey();
    }

    // Verify that the public key is not empty
    for (uint8 i = 0; i < _pubKey.length; ++i) {
      if (_pubKey[i] != 0) {
        break;
      }
      if (i == _pubKey.length - 1) {
        revert AdditionalZkLighter_InvalidPubKey();
      }
    }

    // Verify that the public key is in the field
    for (uint8 i = 0; i < 5; i++) {
      bytes memory elem = _pubKey[(8 * i):(8 * (i + 1))];
      uint64 elemValue = 0;
      for (uint8 j = 0; j < 8; j++) {
        elemValue = elemValue + (uint64(uint8(elem[j])) << (8 * j));
      }
      if (elemValue >= GOLDILOCKS_MODULUS) {
        revert AdditionalZkLighter_InvalidPubKey();
      }
    }

    uint48 _masterAccountIndex = getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_AccountIsNotRegistered();
    }

    // Add priority request to the queue
    TxTypes.ChangePubKey memory _tx = TxTypes.ChangePubKey({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      apiKeyIndex: _apiKeyIndex,
      pubKey: _pubKey
    });
    bytes memory pubData = TxTypes.writeChangePubKeyPubDataForPriorityQueue(_tx);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1ChangePubKey, pubData, pubData);
    emit ChangePubKey(_accountIndex, _apiKeyIndex, _pubKey);
  }

  /// @notice Create new market and an order book
  /// @param _size_decimals [metadata] Number of decimals to represent size of an order in the order book
  /// @param _price_decimals [metadata] Number of decimals to represent price of an order in the order book
  /// @param _symbol [metadata] symbol of the market, formatted as bytes32
  /// @param _params Market parameters
  function createMarket(uint8 _size_decimals, uint8 _price_decimals, bytes32 _symbol, TxTypes.CreateMarket calldata _params) external onlyActive {
    governance.requireGovernor(msg.sender);

    if (_size_decimals + _price_decimals > USDC_DECIMALS) {
      revert AdditionalZkLighter_InvalidMarketDecimals();
    }

    validateCreateMarketParams(_params);

    // Add priority request to the queue
    bytes memory priorityRequest = TxTypes.writeCreateMarketPubDataForPriorityQueue(_params);
    bytes memory metadata = TxTypes.writeCreateMarketPubDataForPriorityQueueWithMetadata(priorityRequest, _size_decimals, _price_decimals, _symbol);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1CreateMarket, priorityRequest, metadata);
    emit CreateMarket(_params, _size_decimals, _price_decimals, _symbol);
  }

  function validateCreateMarketParams(TxTypes.CreateMarket calldata _params) internal pure {
    if (_params.marketIndex > MAX_MARKET_INDEX) {
      revert AdditionalZkLighter_InvalidMarketIndex();
    }

    if (_params.quoteMultiplier == 0 || _params.quoteMultiplier > MAX_QUOTE_MULTIPLIER) {
      revert AdditionalZkLighter_InvalidQuoteMultiplier();
    }

    if (_params.makerFee > FEE_TICK || _params.takerFee > FEE_TICK || _params.liquidationFee > FEE_TICK) {
      revert AdditionalZkLighter_InvalidFeeAmount();
    }
    if (
      _params.closeOutMarginFraction == 0 ||
      _params.closeOutMarginFraction > _params.maintenanceMarginFraction ||
      _params.maintenanceMarginFraction > _params.minInitialMarginFraction ||
      _params.minInitialMarginFraction > _params.defaultInitialMarginFraction ||
      _params.defaultInitialMarginFraction > MARGIN_TICK
    ) {
      revert AdditionalZkLighter_InvalidMarginFraction();
    }

    if (_params.interestRate > FUNDING_RATE_TICK) {
      revert AdditionalZkLighter_InvalidInterestRate();
    }

    if (
      _params.minBaseAmount == 0 ||
      _params.minBaseAmount > MAX_ORDER_BASE_AMOUNT ||
      _params.minQuoteAmount == 0 ||
      _params.minQuoteAmount > MAX_ORDER_QUOTE_AMOUNT
    ) {
      revert AdditionalZkLighter_InvalidMinAmounts();
    }

    if (_params.fundingClampSmall > FUNDING_RATE_TICK || _params.fundingClampBig > FUNDING_RATE_TICK) {
      revert AdditionalZkLighter_InvalidFundingClamps();
    }

    if (_params.orderQuoteLimit > _params.openInterestLimit) {
      revert AdditionalZkLighter_InvalidOpenInterestLimit();
    }

    if (_params.minQuoteAmount > _params.orderQuoteLimit) {
      revert AdditionalZkLighter_InvalidOrderQuoteLimit();
    }
  }

  /// @notice Update order book status
  /// @param _params Order book update parameters
  function updateMarket(TxTypes.UpdateMarket calldata _params) external onlyActive {
    governance.requireGovernor(msg.sender);

    validateUpdateMarketParams(_params);

    // Add priority request to the queue
    bytes memory pubData = TxTypes.writeUpdateMarketPubDataForPriorityQueue(_params);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1UpdateMarket, pubData, pubData);
    emit UpdateMarket(_params);
  }

  function validateUpdateMarketParams(TxTypes.UpdateMarket calldata _params) internal pure {
    if (_params.marketIndex > MAX_MARKET_INDEX) {
      revert AdditionalZkLighter_InvalidMarketIndex();
    }
    if (_params.status != uint8(MarketStatus.ACTIVE) && _params.status != uint8(MarketStatus.NONE)) {
      revert AdditionalZkLighter_InvalidMarketStatus();
    }
    if (_params.makerFee > FEE_TICK || _params.takerFee > FEE_TICK || _params.liquidationFee > FEE_TICK) {
      revert AdditionalZkLighter_InvalidFeeAmount();
    }
    if (
      _params.closeOutMarginFraction == 0 ||
      _params.closeOutMarginFraction > _params.maintenanceMarginFraction ||
      _params.maintenanceMarginFraction > _params.minInitialMarginFraction ||
      _params.minInitialMarginFraction > _params.defaultInitialMarginFraction ||
      _params.defaultInitialMarginFraction > MARGIN_TICK
    ) {
      revert AdditionalZkLighter_InvalidMarginFraction();
    }

    if (_params.interestRate > FUNDING_RATE_TICK) {
      revert AdditionalZkLighter_InvalidInterestRate();
    }

    if (
      _params.minBaseAmount == 0 ||
      _params.minBaseAmount > MAX_ORDER_BASE_AMOUNT ||
      _params.minQuoteAmount == 0 ||
      _params.minQuoteAmount > MAX_ORDER_QUOTE_AMOUNT
    ) {
      revert AdditionalZkLighter_InvalidMinAmounts();
    }

    if (_params.fundingClampSmall > FUNDING_RATE_TICK || _params.fundingClampBig > FUNDING_RATE_TICK) {
      revert AdditionalZkLighter_InvalidFundingClamps();
    }

    if (_params.orderQuoteLimit > _params.openInterestLimit) {
      revert AdditionalZkLighter_InvalidOpenInterestLimit();
    }

    if (_params.minQuoteAmount > _params.orderQuoteLimit) {
      revert AdditionalZkLighter_InvalidOrderQuoteLimit();
    }
  }

  /// @notice Cancels all orders
  function cancelAllOrders(uint48 _accountIndex) external nonReentrant onlyActive {
    if (_accountIndex > MAX_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }
    uint48 _masterAccountIndex = getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_AccountIsNotRegistered();
    }

    // Add priority request to the queue
    TxTypes.CancelAllOrders memory _tx = TxTypes.CancelAllOrders({accountIndex: _accountIndex, masterAccountIndex: _masterAccountIndex});
    bytes memory pubData = TxTypes.writeCancelAllOrdersPubDataForPriorityQueue(_tx);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1CancelAllOrders, pubData, pubData);
    emit CancelAllOrders(_accountIndex);
  }

  /// @notice Withdraw USDC from zkLighter
  /// @param _accountIndex Account index
  /// @param _usdcAmount Amount to withdraw
  function withdraw(uint48 _accountIndex, uint64 _usdcAmount) external nonReentrant onlyActive {
    if (_accountIndex > MAX_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }
    uint48 _masterAccountIndex = getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_AccountIsNotRegistered();
    }

    if (_usdcAmount == 0 || _usdcAmount > MAX_EXCHANGE_USDC_AMOUNT) {
      revert AdditionalZkLighter_InvalidWithdrawAmount();
    }

    TxTypes.L1Withdraw memory _tx = TxTypes.L1Withdraw({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      usdcAmount: _usdcAmount
    });

    bytes memory pubData = TxTypes.writeWithdrawPubDataForPriorityQueue(_tx);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1Withdraw, pubData, pubData);
    emit Withdraw(_accountIndex, _usdcAmount);
  }

  /// @notice Create an order for a Lighter account
  /// @param _accountIndex Account index
  /// @param _marketIndex Market index
  /// @param _baseAmount Amount of base token
  /// @param _price Price of the order
  /// @param _isAsk Flag to indicate if the order is ask or bid
  /// @param _orderType Order type
  function createOrder(
    uint48 _accountIndex,
    uint8 _marketIndex,
    uint48 _baseAmount,
    uint32 _price,
    uint8 _isAsk,
    uint8 _orderType
  ) external nonReentrant onlyActive {
    if (_accountIndex > MAX_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }
    uint48 _masterAccountIndex = getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_AccountIsNotRegistered();
    }
    if (_isAsk != 0 && _isAsk != 1) {
      revert AdditionalZkLighter_InvalidCreateOrderParameters();
    }

    if (_orderType != uint8(TxTypes.OrderType.LimitOrder) && _orderType != uint8(TxTypes.OrderType.MarketOrder)) {
      revert AdditionalZkLighter_InvalidCreateOrderParameters();
    }

    if (_baseAmount != NIL_ORDER_BASE_AMOUNT && (_baseAmount > MAX_ORDER_BASE_AMOUNT || _baseAmount < MIN_ORDER_BASE_AMOUNT)) {
      revert AdditionalZkLighter_InvalidCreateOrderParameters();
    }

    if (_price > MAX_ORDER_PRICE || _price < MIN_ORDER_PRICE) {
      revert AdditionalZkLighter_InvalidCreateOrderParameters();
    }

    TxTypes.CreateOrder memory _tx = TxTypes.CreateOrder({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      marketIndex: _marketIndex,
      baseAmount: _baseAmount,
      price: _price,
      isAsk: _isAsk,
      orderType: _orderType
    });

    bytes memory pubData = TxTypes.writeCreateOrderPubDataForPriorityQueue(_tx);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1CreateOrder, pubData, pubData);
    emit CreateOrder(_tx);
  }

  /// @notice Burn shares of an account in a public pool
  /// @param _accountIndex Account index
  /// @param _publicPoolIndex Public pool index
  /// @param _shareAmount Amount of shares to burn
  function burnShares(uint48 _accountIndex, uint48 _publicPoolIndex, uint64 _shareAmount) external nonReentrant onlyActive {
    if (_accountIndex > MAX_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }
    if (_accountIndex == _publicPoolIndex) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }
    uint48 _masterAccountIndex = getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_AccountIsNotRegistered();
    }

    if (_publicPoolIndex > MAX_ACCOUNT_INDEX || _publicPoolIndex <= MAX_MASTER_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }
    if (_shareAmount < MIN_POOL_SHARES_TO_MINT_OR_BURN || _shareAmount > MAX_POOL_SHARES_TO_MINT_OR_BURN) {
      revert AdditionalZkLighter_InvalidShareAmount();
    }

    TxTypes.BurnShares memory _tx = TxTypes.BurnShares({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      publicPoolIndex: _publicPoolIndex,
      sharesAmount: _shareAmount
    });
    bytes memory pubData = TxTypes.writeBurnSharesPubDataForPriorityQueue(_tx);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1BurnShares, pubData, pubData);
    emit BurnShares(_tx);
  }

  /// @notice Register deposit request - pack pubdata, add into onchainOpsCheck and emit OnchainDeposit event
  /// @param _amount Asset amount
  /// @param _toAddress Receiver Account's L1 address
  function registerDeposit(uint64 _amount, address _toAddress) internal {
    uint48 _toAccountIndex = getAccountIndexFromAddress(_toAddress);
    // No account could be found for the address
    if (_toAccountIndex <= MAX_SYSTEM_ACCOUNT_INDEX) {
      _toAddress = address(0);
    } else if (_toAccountIndex == NIL_ACCOUNT_INDEX) {
      ++lastAccountIndex;
      _toAccountIndex = lastAccountIndex;
      if (_toAccountIndex > MAX_MASTER_ACCOUNT_INDEX) {
        revert AdditionalZkLighter_TooManyRegisteredAccounts();
      }
      addressToAccountIndex[_toAddress] = _toAccountIndex;
    }
    // Add priority request to the queue
    TxTypes.Deposit memory _tx = TxTypes.Deposit({accountIndex: _toAccountIndex, toAddress: _toAddress, amount: _amount});
    bytes memory pubData = TxTypes.writeDepositPubDataForPriorityQueue(_tx);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1Deposit, pubData, pubData);
    emit Deposit(_toAccountIndex, _toAddress, _amount);
  }

  /// @notice Saves priority request in storage
  /// @dev Calculates expiration timestamp of the request and stores the request in priorityRequests
  /// @param _pubdataType Priority request public data type
  /// @param _priorityRequest Request public data that is hashed and stored in priorityRequests
  /// @param _pubData Request public data that is emitted in NewPriorityRequest event, could be different from _priorityRequest
  function addPriorityRequest(uint8 _pubdataType, bytes memory _priorityRequest, bytes memory _pubData) internal {
    // Expiration timestamp is current block number + priority expiration delta
    uint64 expirationTimestamp = SafeCast.toUint64(block.timestamp + PRIORITY_EXPIRATION);
    uint64 nextPriorityRequestId = executedPriorityRequestCount + openPriorityRequestCount;
    bytes32 pubDataPrefix = bytes32(0);
    if (nextPriorityRequestId > 0) {
      pubDataPrefix = priorityRequests[nextPriorityRequestId - 1].prefixHash;
    }
    bytes memory paddedPubData = new bytes(MAX_PRIORITY_REQUEST_PUBDATA_SIZE);
    for (uint256 i = 0; i < _priorityRequest.length; ++i) {
      paddedPubData[i] = _priorityRequest[i];
    }
    priorityRequests[nextPriorityRequestId] = PriorityRequest({
      prefixHash: keccak256(abi.encodePacked(pubDataPrefix, paddedPubData)),
      expirationTimestamp: expirationTimestamp
    });
    emit NewPriorityRequest(msg.sender, nextPriorityRequestId, _pubdataType, _pubData, expirationTimestamp);
    ++openPriorityRequestCount;
  }

  function increaseBalanceToWithdraw(uint48 _masterAccountIndex, uint128 _amount) internal {
    uint128 balance = pendingBalance[_masterAccountIndex].balanceToWithdraw;
    pendingBalance[_masterAccountIndex] = PendingBalance(balance + _amount, FILLED_GAS_RESERVE_VALUE);
  }

  function createExitCommitment(
    uint256 stateRoot,
    uint48 _accountIndex,
    uint48 _masterAccountIndex,
    uint128 _totalAccountValue
  ) internal pure returns (bytes32) {
    bytes32 converted = sha256(abi.encodePacked(stateRoot, _accountIndex, _masterAccountIndex, _totalAccountValue));
    return converted;
  }

  /// @notice Performs exit from zkLighter in desert mode
  function performDesert(uint48 _accountIndex, uint48 _masterAccountIndex, uint128 _totalAccountValue, bytes calldata proof) external nonReentrant {
    // Must be in desert mode
    if (!desertMode) {
      revert AdditionalZkLighter_DesertModeInactive();
    }

    if (accountPerformedDesert[_accountIndex]) {
      revert AdditionalZkLighter_DesertPerformedForAccount();
    }

    uint256[] memory inputs = new uint256[](1);
    bytes32 commitment = createExitCommitment(uint256(stateRoot), _accountIndex, _masterAccountIndex, _totalAccountValue);
    inputs[0] = uint256(commitment) % BN254_MODULUS;
    bool success = desertVerifier.Verify(proof, inputs);
    if (!success) {
      revert AdditionalZkLighter_DesertVerifyProofFailed();
    }

    increaseBalanceToWithdraw(_masterAccountIndex, _totalAccountValue);
    accountPerformedDesert[_accountIndex] = true;
  }

  /// @param _n Number of requests to cancel
  /// @param _priorityPubData The array of the priority pub data since the last executed pub data
  function cancelOutstandingDepositsForDesertMode(uint64 _n, bytes[] memory _priorityPubData) external nonReentrant {
    // Must be in desert mode
    if (!desertMode) {
      revert AdditionalZkLighter_DesertModeInactive();
    }

    if (openPriorityRequestCount == 0 || _n == 0) {
      revert AdditionalZkLighter_NoOutstandingDepositsForCancelation();
    }

    if (_n > openPriorityRequestCount || _n != _priorityPubData.length) {
      revert AdditionalZkLighter_InvalidParamsForCancelOutstandingDeposits();
    }

    uint64 startIndex = executedPriorityRequestCount;

    bytes32 pubDataPrefixHash = bytes32(0);
    if (executedPriorityRequestCount > 0) {
      pubDataPrefixHash = priorityRequests[executedPriorityRequestCount - 1].prefixHash;
    }

    uint64 currentPubDataIdx = 0;
    for (uint64 id = startIndex; id < startIndex + _n; ++id) {
      if (_priorityPubData[currentPubDataIdx].length > MAX_PRIORITY_REQUEST_PUBDATA_SIZE || _priorityPubData[currentPubDataIdx].length == 0) {
        revert AdditionalZkLighter_InvalidParamsForCancelOutstandingDeposits();
      }

      bytes memory paddedPubData = new bytes(MAX_PRIORITY_REQUEST_PUBDATA_SIZE);
      for (uint256 i = 0; i < _priorityPubData[currentPubDataIdx].length; ++i) {
        paddedPubData[i] = _priorityPubData[currentPubDataIdx][i];
      }

      pubDataPrefixHash = keccak256(abi.encodePacked(pubDataPrefixHash, paddedPubData));
      if (pubDataPrefixHash != priorityRequests[id].prefixHash) {
        revert AdditionalZkLighter_DepositPubdataHashMismatch();
      }

      if (uint8(_priorityPubData[currentPubDataIdx][0]) == TxTypes.PriorityPubDataTypeL1Deposit) {
        if (_priorityPubData[currentPubDataIdx].length != TxTypes.DEPOSIT_PUB_DATA_SIZE) {
          revert AdditionalZkLighter_DepositPubdataHashMismatch();
        }
        bytes memory depositPubdata = _priorityPubData[currentPubDataIdx];
        (uint48 accountIndex, uint64 amount) = TxTypes.readDepositForDesertMode(depositPubdata);
        increaseBalanceToWithdraw(accountIndex, amount);
      }

      ++currentPubDataIdx;
    }

    openPriorityRequestCount -= _n;
    executedPriorityRequestCount += _n;
  }
}
