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
  error AdditionalZkLighter_InvalidAssetIndex();
  error AdditionalZkLighter_InvalidDepositAmount();
  error AdditionalZkLighter_InvalidWithdrawAmount();
  error AdditionalZkLighter_InvalidAccountIndex();
  error AdditionalZkLighter_InvalidDepositBatchLength();
  error AdditionalZkLighter_InvalidApiKeyIndex();
  error AdditionalZkLighter_InvalidPubKey();
  error AdditionalZkLighter_InvalidMarketStatus();
  error AdditionalZkLighter_InvalidMarginParameters();
  error AdditionalZkLighter_InvalidExtensionMultiplier();
  error AdditionalZkLighter_InvalidIndexPriceDivider();
  error AdditionalZkLighter_InvalidFeeAmount();
  error AdditionalZkLighter_InvalidMarginFraction();
  error AdditionalZkLighter_InvalidMinAmounts();
  error AdditionalZkLighter_InvalidConfigPeriod();
  error AdditionalZkLighter_InvalidMarketType();
  error AdditionalZkLighter_InvalidShareAmount();
  error AdditionalZkLighter_InvalidCreateOrderParameters();
  error AdditionalZkLighter_AccountIsNotRegistered();
  error AdditionalZkLighter_InvalidBatch();
  error AdditionalZkLighter_InvalidFundingClampsOrInterestRate();
  error AdditionalZkLighter_InvalidMarketLimits();
  error AdditionalZkLighter_StateRootUpgradeVerifierFailed();

  function updateStateRoot(
    StoredBatchInfo calldata _lastStoredBatch,
    bytes32 _stateRoot,
    bytes32 _validiumRoot,
    bytes calldata proof
  ) external nonReentrant onlyActive {
    governance.isActiveValidator(msg.sender);

    if (storedBatchHashes[committedBatchesCount] != hashStoredBatchInfo(_lastStoredBatch)) {
      revert AdditionalZkLighter_InvalidBatch();
    }

    if (executedBatchesCount != committedBatchesCount) {
      revert AdditionalZkLighter_InvalidBatch();
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
      revert AdditionalZkLighter_StateRootUpgradeVerifierFailed();
    }

    stateRoot = _stateRoot;
    validiumRoot = _validiumRoot;
    lastVerifiedStateRoot = _stateRoot;
    lastVerifiedValidiumRoot = _validiumRoot;
    stateRootUpdates[committedBatchesCount] = _stateRoot;

    emit StateRootUpdate(committedBatchesCount, _lastStoredBatch.stateRoot, _stateRoot);
  }

  /// @notice Deposit ETH or ERC20 asset to zkLighter
  /// @param _assetIndex Asset index
  /// @param _routeType Route type
  /// @param _amount ETH or ERC20 asset amount to deposit
  /// @param _to The receiver L1 address
  function _deposit(address[] memory _to, uint16 _assetIndex, TxTypes.RouteType _routeType, uint256[] memory _amount) internal {
    AssetConfig memory assetConfig = validateAndGetAssetConfig(_assetIndex);
    if (_assetIndex != NATIVE_ASSET_INDEX && msg.value != 0) {
      revert AdditionalZkLighter_InvalidDepositAmount();
    }

    uint256 minDeposit = uint256(assetConfig.minDepositTicks) * uint256(assetConfig.tickSize);
    uint256 depositCap = uint256(assetConfig.depositCapTicks) * uint256(assetConfig.tickSize);
    uint256 totalAmount = 0;
    for (uint256 i = 0; i < _amount.length; ++i) {
      totalAmount += _amount[i];
      if (_amount[i] < minDeposit || _amount[i] % assetConfig.tickSize != 0) {
        revert AdditionalZkLighter_InvalidDepositAmount();
      }
      if (_to[i] == address(0)) {
        revert AdditionalZkLighter_AccountIsNotRegistered();
      }
    }

    uint256 balanceAfter = 0;
    if (_assetIndex == NATIVE_ASSET_INDEX) {
      balanceAfter = address(this).balance;
      if (msg.value != totalAmount) {
        revert AdditionalZkLighter_InvalidDepositAmount();
      }
    } else {
      IERC20 _token = IERC20(assetConfig.tokenAddress);
      uint256 balanceBefore = _token.balanceOf(address(this));
      SafeERC20.safeTransferFrom(_token, msg.sender, address(this), totalAmount);
      balanceAfter = _token.balanceOf(address(this));
      if (balanceAfter < balanceBefore + totalAmount) {
        revert AdditionalZkLighter_InvalidDepositAmount();
      } else if (balanceAfter > balanceBefore + totalAmount) {
        uint256 excessAmount = balanceAfter - (balanceBefore + totalAmount);
        uint64 baseExcessAmount = SafeCast.toUint64(excessAmount / assetConfig.tickSize);
        increaseBalanceToWithdraw(TREASURY_ACCOUNT_INDEX, _assetIndex, baseExcessAmount);
      }
    }

    if (balanceAfter > depositCap) {
      revert AdditionalZkLighter_InvalidDepositAmount();
    }
    for (uint256 i = 0; i < _amount.length; ++i) {
      uint64 baseAmount = SafeCast.toUint64(_amount[i] / assetConfig.tickSize);
      registerDeposit(_to[i], _assetIndex, _routeType, baseAmount);
    }
  }

  /// @notice Deposit asset to Lighter
  /// @param _to The receiver L1 address
  /// @param _assetIndex Asset index
  /// @param _routeType Route type
  /// @param _amount asset amount to deposit
  function deposit(address _to, uint16 _assetIndex, TxTypes.RouteType _routeType, uint256 _amount) external payable nonReentrant onlyActive {
    uint256[] memory amount = new uint256[](1);
    amount[0] = _amount;
    address[] memory to = new address[](1);
    to[0] = _to;
    _deposit(to, _assetIndex, _routeType, amount);
  }

  /// @notice Deposit USDC to Lighter for multiple users
  /// @param _amount Array of USDC Token amounts
  /// @param _to Array of receiver L1 addresses
  /// @param _accountIndex Array of account index values, will be used in the future
  function depositBatch(uint64[] calldata _amount, address[] calldata _to, uint48[] calldata _accountIndex) external nonReentrant onlyActive {
    if (_amount.length != _to.length || _amount.length != _accountIndex.length || _amount.length == 0 || _amount.length > MAX_BATCH_DEPOSIT_LENGTH) {
      revert AdditionalZkLighter_InvalidDepositBatchLength();
    }
    uint256[] memory amount = new uint256[](_amount.length);
    for (uint256 i = 0; i < _amount.length; ++i) {
      amount[i] = uint256(_amount[i]);
    }
    _deposit(_to, USDC_ASSET_INDEX, TxTypes.RouteType.Perps, amount);
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

    // Verify that the public key is in connonical form and not zero
    bool isZero = true;
    for (uint8 i = 0; i < 5; i++) {
      bytes memory elem = _pubKey[(8 * i):(8 * (i + 1))];
      uint64 elemValue = 0;
      for (uint8 j = 0; j < 8; j++) {
        elemValue = elemValue + (uint64(uint8(elem[j])) << (8 * j));
      }
      if (elemValue >= GOLDILOCKS_MODULUS) {
        revert AdditionalZkLighter_InvalidPubKey();
      }
      if (elemValue != 0) {
        isZero = false;
      }
    }
    if (isZero) {
      revert AdditionalZkLighter_InvalidPubKey();
    }

    // Add priority request to the queue
    TxTypes.ChangePubKey memory _tx = TxTypes.ChangePubKey({
      accountIndex: _accountIndex,
      masterAccountIndex: validateAndGetAccountIndexFromAddress(msg.sender),
      apiKeyIndex: _apiKeyIndex,
      pubKey: _pubKey
    });
    bytes memory pubData = TxTypes.writeChangePubKeyPubDataForPriorityQueue(_tx);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1ChangePubKey, pubData, pubData);
  }

  /// @notice Create new asset
  /// @param _params Config parameters
  function setSystemConfig(TxTypes.SetSystemConfig calldata _params) external nonReentrant onlyActive {
    governance.requireGovernor(msg.sender);
    if (_params.liquidityPoolCooldownPeriod > MAX_CONFIG_PERIOD || _params.stakingPoolLockupPeriod > MAX_CONFIG_PERIOD) {
      revert AdditionalZkLighter_InvalidConfigPeriod();
    }
    if (_params.liquidityPoolIndex > MAX_ACCOUNT_INDEX || _params.stakingPoolIndex > MAX_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }
    validateMarketFeeParams(_params.maxIntegratorPerpsTakerFee, _params.maxIntegratorPerpsMakerFee);
    validateMarketFeeParams(_params.maxIntegratorSpotTakerFee, _params.maxIntegratorSpotMakerFee);
    bytes memory priorityRequest = TxTypes.writeSetSystemConfigPubDataForPriorityQueue(_params);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1SetSystemConfig, priorityRequest, priorityRequest);
  }

  function validateCommonAssetParams(
    uint16 assetIndex,
    uint64 minL2TransferAmount,
    uint64 minL2WithdrawalAmount,
    uint8 marginMode,
    uint16 loanToValue,
    uint16 liquidationThreshold,
    uint16 liquidationFactor,
    uint32 liquidationFee
  ) internal pure {
    // Performs asset parameter range checks, if there is inconsistency between parameters, operation will be noop
    if (minL2TransferAmount == 0 || minL2TransferAmount > MAX_DEPOSIT_CAP_TICKS) {
      revert AdditionalZkLighter_InvalidMinAmounts();
    }
    if (minL2WithdrawalAmount == 0 || minL2WithdrawalAmount > MAX_DEPOSIT_CAP_TICKS) {
      revert AdditionalZkLighter_InvalidMinAmounts();
    }
    if (marginMode == uint8(TxTypes.AssetMarginMode.Enabled)) {
      if (
        loanToValue == 0 || loanToValue > liquidationThreshold || liquidationThreshold > liquidationFactor || liquidationFactor > ASSET_MARGIN_TICK
      ) {
        revert AdditionalZkLighter_InvalidMarginParameters();
      }
      if (liquidationFee + uint32(liquidationFactor) * uint32(FEE_TICK / ASSET_MARGIN_TICK) > FEE_TICK) {
        revert AdditionalZkLighter_InvalidMarginParameters();
      }
      if (assetIndex == USDC_ASSET_INDEX && (loanToValue != ASSET_MARGIN_TICK || liquidationFee != 0)) {
        revert AdditionalZkLighter_InvalidMarginParameters();
      }
    } else if (marginMode == uint8(TxTypes.AssetMarginMode.Disabled)) {
      if (assetIndex == USDC_ASSET_INDEX) {
        revert AdditionalZkLighter_InvalidMarginParameters();
      }
      if (loanToValue != 0 || liquidationThreshold != 0 || liquidationFactor != 0 || liquidationFee != 0) {
        revert AdditionalZkLighter_InvalidMarginParameters();
      }
    } else {
      revert AdditionalZkLighter_InvalidMarginParameters();
    }
  }

  /// @notice Create new asset
  /// @param _l1Decimals [metadata] Number of decimals of the asset on L1
  /// @param _l2decimals [metadata] Number of decimals of the asset in Lighter
  /// @param _priceDecimals [metadata] Number of decimals to represent price of the asset in Lighter
  /// @param _symbol [metadata] symbol of the asset, formatted as bytes32
  /// @param _params Asset parameters
  function registerAsset(
    uint8 _l1Decimals,
    uint8 _l2decimals,
    uint8 _priceDecimals,
    bytes32 _symbol,
    TxTypes.RegisterAsset calldata _params
  ) external nonReentrant onlyActive {
    governance.requireGovernor(msg.sender);

    AssetConfig memory config = validateAndGetAssetConfig(_params.assetIndex);
    if (_params.extensionMultiplier != config.extensionMultiplier) {
      revert AdditionalZkLighter_InvalidExtensionMultiplier();
    }
    if (_params.indexPriceDivider == 0 || _params.indexPriceDivider > MAX_ASSET_EXTENSION_MULTIPLIER) {
      revert AdditionalZkLighter_InvalidIndexPriceDivider();
    }
    validateCommonAssetParams(
      _params.assetIndex,
      _params.minL2TransferAmount,
      _params.minL2WithdrawalAmount,
      _params.marginMode,
      _params.loanToValue,
      _params.liquidationThreshold,
      _params.liquidationFactor,
      _params.liquidationFee
    );
    bytes memory priorityRequest = TxTypes.writeRegisterAssetPubDataForPriorityQueue(_params);
    bytes memory metadata = TxTypes.writeRegisterAssetPubDataForPriorityQueueWithMetadata(
      priorityRequest,
      _l1Decimals,
      _l2decimals,
      _priceDecimals,
      config.tickSize,
      config.tokenAddress,
      _symbol
    );
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1RegisterAsset, priorityRequest, metadata);
  }

  /// @notice Update asset parameters
  /// @param _params Asset update parameters
  function updateAsset(TxTypes.UpdateAsset calldata _params) external nonReentrant onlyActive {
    governance.requireGovernor(msg.sender);
    validateAssetIndex(_params.assetIndex);
    validateCommonAssetParams(
      _params.assetIndex,
      _params.minL2TransferAmount,
      _params.minL2WithdrawalAmount,
      _params.marginMode,
      _params.loanToValue,
      _params.liquidationThreshold,
      _params.liquidationFactor,
      _params.liquidationFee
    );
    bytes memory pubData = TxTypes.writeUpdateAssetPubDataForPriorityQueue(_params);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1UpdateAsset, pubData, pubData);
  }

  /// @notice Create new market and an order book
  /// @param _size_decimals [metadata] Number of decimals to represent size of an order in the order book
  /// @param _price_decimals [metadata] Number of decimals to represent price of an order in the order book
  /// @param _symbol [metadata] symbol of the market, formatted as bytes32
  /// @param _params Market parameters
  function createMarket(
    uint8 _size_decimals,
    uint8 _price_decimals,
    bytes32 _symbol,
    TxTypes.CreateMarket calldata _params
  ) external nonReentrant onlyActive {
    governance.requireGovernor(msg.sender);

    validateCreateMarketParams(_params);

    // Add priority request to the queue
    bytes memory priorityRequest = TxTypes.writeCreateMarketPubDataForPriorityQueue(_params);
    bytes memory metadata = TxTypes.writeCreateMarketPubDataForPriorityQueueWithMetadata(priorityRequest, _size_decimals, _price_decimals, _symbol);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1CreateMarket, priorityRequest, metadata);
    emit CreateMarket(_params, _size_decimals, _price_decimals, _symbol);
  }

  function validateMarketFeeParams(uint32 takerFee, uint32 makerFee) internal pure {
    if (takerFee > FEE_TICK || makerFee > FEE_TICK) {
      revert AdditionalZkLighter_InvalidFeeAmount();
    }
  }

  function validateCommonPerpMarketParams(TxTypes.CommonPerpsData memory perpParams) internal pure {
    validateMarketFeeParams(perpParams.takerFee, perpParams.makerFee);
    if (perpParams.liquidationFee > FEE_TICK) {
      revert AdditionalZkLighter_InvalidFeeAmount();
    }
    if (
      perpParams.closeOutMarginFraction == 0 ||
      perpParams.closeOutMarginFraction > perpParams.maintenanceMarginFraction ||
      perpParams.maintenanceMarginFraction > perpParams.minInitialMarginFraction ||
      perpParams.minInitialMarginFraction > perpParams.defaultInitialMarginFraction ||
      perpParams.defaultInitialMarginFraction > MARGIN_TICK
    ) {
      revert AdditionalZkLighter_InvalidMarginFraction();
    }
    if (perpParams.interestRate > FUNDING_RATE_TICK) {
      revert AdditionalZkLighter_InvalidFundingClampsOrInterestRate();
    }
    if (perpParams.fundingClampSmall > FUNDING_RATE_TICK || perpParams.fundingClampBig > FUNDING_RATE_TICK) {
      revert AdditionalZkLighter_InvalidFundingClampsOrInterestRate();
    }
    if (
      perpParams.minBaseAmount == 0 ||
      perpParams.minBaseAmount > MAX_ORDER_BASE_AMOUNT ||
      perpParams.minQuoteAmount == 0 ||
      perpParams.minQuoteAmount > MAX_ORDER_QUOTE_AMOUNT
    ) {
      revert AdditionalZkLighter_InvalidMinAmounts();
    }
    if (perpParams.orderQuoteLimit > MAX_ORDER_QUOTE_AMOUNT || perpParams.minQuoteAmount > perpParams.orderQuoteLimit) {
      revert AdditionalZkLighter_InvalidMarketLimits();
    }
    if (perpParams.openInterestLimit < perpParams.orderQuoteLimit || perpParams.openInterestLimit > MAX_MARKET_OPEN_INTEREST) {
      revert AdditionalZkLighter_InvalidMarketLimits();
    }
  }

  function validateCommonSpotMarketParams(TxTypes.CommonSpotData memory spotParams) internal pure {
    validateMarketFeeParams(spotParams.takerFee, spotParams.makerFee);
    if (
      spotParams.minBaseAmount == 0 ||
      spotParams.minBaseAmount > MAX_ORDER_BASE_AMOUNT ||
      spotParams.minQuoteAmount == 0 ||
      spotParams.minQuoteAmount > MAX_ORDER_QUOTE_AMOUNT
    ) {
      revert AdditionalZkLighter_InvalidMinAmounts();
    }
    if (spotParams.orderQuoteLimit > MAX_ORDER_QUOTE_AMOUNT || spotParams.minQuoteAmount > spotParams.orderQuoteLimit) {
      revert AdditionalZkLighter_InvalidMarketLimits();
    }
  }

  function validateCreateMarketParams(TxTypes.CreateMarket calldata _params) internal view {
    if (_params.marketType == TxTypes.MarketType.Perps) {
      TxTypes.CreateMarketPerpsData memory perpParams = TxTypes.readCreateMarketPerpsData(_params.marketData);
      if (_params.marketIndex > MAX_PERPS_MARKET_INDEX) {
        revert AdditionalZkLighter_InvalidMarketType();
      }
      if (perpParams.quoteMultiplier == 0 || perpParams.quoteMultiplier > MAX_QUOTE_MULTIPLIER) {
        revert AdditionalZkLighter_InvalidExtensionMultiplier();
      }
      validateCommonPerpMarketParams(perpParams.common);
    } else if (_params.marketType == TxTypes.MarketType.Spot) {
      TxTypes.CreateMarketSpotData memory spotParams = TxTypes.readCreateMarketSpotData(_params.marketData);
      if (_params.marketIndex < MIN_SPOT_MARKET_INDEX || _params.marketIndex > MAX_SPOT_MARKET_INDEX) {
        revert AdditionalZkLighter_InvalidMarketType();
      }
      if (spotParams.baseAssetIndex == spotParams.quoteAssetIndex) {
        revert AdditionalZkLighter_InvalidAssetIndex();
      }
      validateAssetIndex(spotParams.baseAssetIndex);
      validateAssetIndex(spotParams.quoteAssetIndex);
      if (
        spotParams.sizeExtensionMultiplier == 0 ||
        spotParams.sizeExtensionMultiplier > MAX_ASSET_EXTENSION_MULTIPLIER ||
        spotParams.sizeExtensionMultiplier % Config.FEE_TICK != 0
      ) {
        revert AdditionalZkLighter_InvalidExtensionMultiplier();
      }
      if (
        spotParams.quoteExtensionMultiplier == 0 ||
        spotParams.quoteExtensionMultiplier > MAX_ASSET_EXTENSION_MULTIPLIER ||
        spotParams.quoteExtensionMultiplier % Config.FEE_TICK != 0
      ) {
        revert AdditionalZkLighter_InvalidExtensionMultiplier();
      }
      validateCommonSpotMarketParams(spotParams.common);
    } else {
      revert AdditionalZkLighter_InvalidMarketType();
    }
  }

  /// @notice Update order book status
  /// @param _params Order book update parameters
  function updateMarket(TxTypes.UpdateMarket calldata _params) external nonReentrant onlyActive {
    governance.requireGovernor(msg.sender);
    validateUpdateMarketParams(_params);
    // Add priority request to the queue
    bytes memory pubdata = TxTypes.writeUpdateMarketPubDataForPriorityQueue(_params);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1UpdateMarket, pubdata, pubdata);
    emit UpdateMarket(_params);
  }

  function validateUpdateMarketParams(TxTypes.UpdateMarket calldata _params) internal pure {
    if (_params.marketType == TxTypes.MarketType.Perps) {
      if (_params.marketIndex > MAX_PERPS_MARKET_INDEX) {
        revert AdditionalZkLighter_InvalidMarketType();
      }
      TxTypes.UpdateMarketPerps memory perpParams = TxTypes.readUpdateMarketPerpsData(_params.marketData);
      if (perpParams.status != uint8(MarketStatus.ACTIVE) && perpParams.status != uint8(MarketStatus.NONE)) {
        revert AdditionalZkLighter_InvalidMarketStatus();
      }
      validateCommonPerpMarketParams(perpParams.common);
    } else if (_params.marketType == TxTypes.MarketType.Spot) {
      if (_params.marketIndex < MIN_SPOT_MARKET_INDEX || _params.marketIndex > MAX_SPOT_MARKET_INDEX) {
        revert AdditionalZkLighter_InvalidMarketType();
      }
      TxTypes.UpdateMarketSpot memory spotParams = TxTypes.readUpdateMarketSpotData(_params.marketData);
      if (spotParams.status != uint8(MarketStatus.ACTIVE) && spotParams.status != uint8(MarketStatus.NONE)) {
        revert AdditionalZkLighter_InvalidMarketStatus();
      }
      validateCommonSpotMarketParams(spotParams.common);
    } else {
      revert AdditionalZkLighter_InvalidMarketType();
    }
  }

  /// @notice Cancels all orders
  function cancelAllOrders(uint48 _accountIndex) external nonReentrant onlyActive {
    if (_accountIndex > MAX_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }

    // Add priority request to the queue
    TxTypes.CancelAllOrders memory _tx = TxTypes.CancelAllOrders({
      accountIndex: _accountIndex,
      masterAccountIndex: validateAndGetAccountIndexFromAddress(msg.sender)
    });
    bytes memory pubData = TxTypes.writeCancelAllOrdersPubDataForPriorityQueue(_tx);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1CancelAllOrders, pubData, pubData);
  }

  /// @notice Withdraw ETH or ERC20 from zkLighter
  /// @param _assetIndex Asset index, 0 for ETH
  /// @param _routeType Route type
  /// @param _accountIndex Account index to withdraw from
  /// @param _baseAmount Amount of base token to withdraw, in ticks
  function withdraw(uint48 _accountIndex, uint16 _assetIndex, TxTypes.RouteType _routeType, uint64 _baseAmount) external nonReentrant onlyActive {
    AssetConfig memory assetConfig = validateAndGetAssetConfig(_assetIndex);
    if (assetConfig.withdrawalsEnabled == 0) {
      revert AdditionalZkLighter_InvalidAssetIndex();
    }
    uint256 depositCapTicks = assetConfig.depositCapTicks;
    if (_baseAmount == 0 || _baseAmount > depositCapTicks) {
      revert AdditionalZkLighter_InvalidWithdrawAmount();
    }
    if (_routeType != TxTypes.RouteType.Perps && _routeType != TxTypes.RouteType.Spot) {
      revert AdditionalZkLighter_InvalidWithdrawAmount();
    }

    TxTypes.L1Withdraw memory _tx = TxTypes.L1Withdraw({
      accountIndex: _accountIndex,
      masterAccountIndex: validateAndGetAccountIndexFromAddress(msg.sender),
      assetIndex: _assetIndex,
      routeType: _routeType,
      baseAmount: _baseAmount
    });

    bytes memory pubData = TxTypes.writeWithdrawPubDataForPriorityQueue(_tx);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1Withdraw, pubData, pubData);
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
    uint16 _marketIndex,
    uint48 _baseAmount,
    uint32 _price,
    uint8 _isAsk,
    uint8 _orderType
  ) external nonReentrant onlyActive {
    if (_accountIndex > MAX_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }
    if (_marketIndex > MAX_PERPS_MARKET_INDEX) {
      revert AdditionalZkLighter_InvalidMarketType();
    }
    if (_isAsk > 1) {
      revert AdditionalZkLighter_InvalidCreateOrderParameters();
    }
    if (_orderType != uint8(TxTypes.OrderType.LimitOrder) && _orderType != uint8(TxTypes.OrderType.MarketOrder)) {
      revert AdditionalZkLighter_InvalidCreateOrderParameters();
    }
    // Zero base amount defaults to the position size, thus is not invalid
    if (_baseAmount > MAX_ORDER_BASE_AMOUNT) {
      revert AdditionalZkLighter_InvalidCreateOrderParameters();
    }
    if (_price > MAX_ORDER_PRICE || _price < MIN_ORDER_PRICE) {
      revert AdditionalZkLighter_InvalidCreateOrderParameters();
    }

    TxTypes.CreateOrder memory _tx = TxTypes.CreateOrder({
      accountIndex: _accountIndex,
      masterAccountIndex: validateAndGetAccountIndexFromAddress(msg.sender),
      marketIndex: _marketIndex,
      baseAmount: _baseAmount,
      price: _price,
      isAsk: _isAsk,
      orderType: _orderType
    });

    bytes memory pubData = TxTypes.writeCreateOrderPubDataForPriorityQueue(_tx);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1CreateOrder, pubData, pubData);
  }

  /// @notice Burn shares of an account in a public pool
  /// @param _accountIndex Account index
  /// @param _publicPoolIndex Public pool index
  /// @param _shareAmount Amount of shares to burn
  function burnShares(uint48 _accountIndex, uint48 _publicPoolIndex, uint64 _shareAmount) external nonReentrant onlyActive {
    if (_accountIndex > MAX_ACCOUNT_INDEX || _publicPoolIndex > MAX_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }
    if (_accountIndex == _publicPoolIndex) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }
    if (_publicPoolIndex <= MAX_MASTER_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_InvalidAccountIndex();
    }
    if (_shareAmount < MIN_POOL_SHARES_TO_MINT_OR_BURN || _shareAmount > MAX_POOL_SHARES_TO_MINT_OR_BURN) {
      revert AdditionalZkLighter_InvalidShareAmount();
    }

    TxTypes.BurnShares memory _tx = TxTypes.BurnShares({
      accountIndex: _accountIndex,
      masterAccountIndex: validateAndGetAccountIndexFromAddress(msg.sender),
      publicPoolIndex: _publicPoolIndex,
      sharesAmount: _shareAmount
    });
    bytes memory pubData = TxTypes.writeBurnSharesPubDataForPriorityQueue(_tx);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1BurnShares, pubData, pubData);
  }

  /// @notice Register deposit request - pack pubdata, add into onchainOpsCheck and emit OnchainDeposit event
  /// @param _toAddress Receiver Account's L1 address
  /// @param _assetIndex Asset index
  /// @param _routeType Route type
  /// @param _baseAmount Asset amount
  function registerDeposit(address _toAddress, uint16 _assetIndex, TxTypes.RouteType _routeType, uint64 _baseAmount) internal {
    uint48 _toAccountIndex = getAccountIndexFromAddress(_toAddress);
    // No account could be found for the address
    if (_toAccountIndex <= MAX_SYSTEM_ACCOUNT_INDEX) {
      _toAddress = address(0);
    } else if (_toAccountIndex == NIL_ACCOUNT_INDEX) {
      ++lastAccountIndex;
      _toAccountIndex = lastAccountIndex;
      if (_toAccountIndex > MAX_MASTER_ACCOUNT_INDEX) {
        revert AdditionalZkLighter_InvalidAccountIndex();
      }
      addressToAccountIndex[_toAddress] = _toAccountIndex;
    }
    TxTypes.Deposit memory _tx = TxTypes.Deposit({
      accountIndex: _toAccountIndex,
      toAddress: _toAddress,
      assetIndex: _assetIndex,
      routeType: _routeType,
      baseAmount: _baseAmount
    });
    bytes memory pubData = TxTypes.writeDepositPubDataForPriorityQueue(_tx);
    addPriorityRequest(TxTypes.PriorityPubDataTypeL1Deposit, pubData, pubData);
    emit Deposit(_toAccountIndex, _toAddress, _assetIndex, _routeType, _baseAmount);
  }

  /// @notice Saves priority request in storage
  /// @dev Calculates expiration timestamp of the request and stores the request in priorityRequests
  /// @param _pubdataType Priority request public data type
  /// @param _priorityRequest Request public data that is hashed and stored in priorityRequests
  /// @param _pubDataWithMetadata Request public data that is emitted in NewPriorityRequest event including the metadata
  function addPriorityRequest(uint8 _pubdataType, bytes memory _priorityRequest, bytes memory _pubDataWithMetadata) internal {
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
    emit NewPriorityRequest(msg.sender, nextPriorityRequestId, _pubdataType, _pubDataWithMetadata, expirationTimestamp);
    ++openPriorityRequestCount;
  }

  function increaseBalanceToWithdraw(uint48 _masterAccountIndex, uint16 _assetIndex, uint128 _baseAmount) internal {
    uint128 baseBalance = pendingAssetBalances[_assetIndex][_masterAccountIndex].balanceToWithdraw;
    pendingAssetBalances[_assetIndex][_masterAccountIndex] = PendingBalance(baseBalance + _baseAmount, FILLED_GAS_RESERVE_VALUE);
  }

  function validateAssetIndex(uint16 _assetIndex) internal view {
    if (_assetIndex != NATIVE_ASSET_INDEX && assetConfigs[_assetIndex].tokenAddress == address(0)) {
      revert AdditionalZkLighter_InvalidAssetIndex();
    }
  }

  function validateAndGetAssetConfig(uint16 _assetIndex) internal view returns (AssetConfig memory) {
    AssetConfig memory assetConfig = assetConfigs[_assetIndex];
    if (_assetIndex != NATIVE_ASSET_INDEX && assetConfig.tokenAddress == address(0)) {
      revert AdditionalZkLighter_InvalidAssetIndex();
    }
    return assetConfig;
  }

  function validateAndGetAccountIndexFromAddress(address _address) internal view returns (uint48) {
    uint48 _masterAccountIndex = getAccountIndexFromAddress(_address);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) {
      revert AdditionalZkLighter_AccountIsNotRegistered();
    }
    return _masterAccountIndex;
  }
}
