// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {Config} from "../Config.sol";
import {ExtendableStorage} from "../ExtendableStorage.sol";
import {IGovernance} from "../interfaces/IGovernance.sol";
import {IZkLighterPublic} from "../interfaces/IZkLighter.sol";
import {TxTypes} from "../lib/TxTypes.sol";

/// @notice Core-facing L1 messaging module.
/// @dev Governance and user actions that enqueue Core priority requests live here,
/// and the corresponding events are emitted from this contract.
contract L1CoreMessaging is ReentrancyGuardUpgradeable, Config {
  event ChangePubKey(uint48 accountIndex, uint8 apiKeyIndex, bytes pubKey);
  event CreateMarket(TxTypes.CreateMarket params, uint8 sizeDecimals, uint8 priceDecimals, bytes32 symbol);
  event RegisterAsset(TxTypes.RegisterAsset params, uint8 l1Decimals, uint8 l2Decimals, uint8 priceDecimals, bytes32 symbol);
  event UpdateAsset(TxTypes.UpdateAsset params);
  event SetSystemConfig(TxTypes.SetSystemConfig params);
  event UpdateMarket(TxTypes.UpdateMarket params);
  event CancelAllOrders(uint48 accountIndex);
  event Withdraw(uint48 accountIndex, uint16 assetIndex, TxTypes.RouteType routeType, uint64 baseAmount);
  event CreateOrder(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint64 publicMarketIndex,
    uint48 baseAmount,
    uint32 price,
    uint8 isAsk,
    uint8 orderType
  );
  event BurnShares(uint48 accountIndex, uint48 masterAccountIndex, uint48 publicPoolIndex, uint64 sharesAmount);

  address private immutable l1CoreMessagingImplementation;

  IZkLighterPublic public zkLighter;
  IGovernance public governance;

  error L1CoreMessaging_AssetNotActive();
  error L1CoreMessaging_InvalidWithdrawAmount();
  error L1CoreMessaging_ZeroAddress();
  error L1CoreMessaging_OnlyProxyCanCallInit();
  error L1CoreMessaging_OnlyProxyCanCallUpgrade();
  error L1CoreMessaging_InvalidAssetIndex();
  error L1CoreMessaging_InvalidExtensionMultiplier();
  error L1CoreMessaging_InvalidMinL2TransferAmount();
  error L1CoreMessaging_InvalidMinL2WithdrawalAmount();
  error L1CoreMessaging_InvalidAccountIndex();
  error L1CoreMessaging_InvalidApiKeyIndex();
  error L1CoreMessaging_InvalidPubKey();
  error L1CoreMessaging_AccountIsNotRegistered();
  error L1CoreMessaging_InvalidMarketIndex();
  error L1CoreMessaging_InvalidMarketStatus();
  error L1CoreMessaging_InvalidMarketAssets();
  error L1CoreMessaging_InvalidMarketType();
  error L1CoreMessaging_InvalidQuoteMultiplier();
  error L1CoreMessaging_InvalidFeeAmount();
  error L1CoreMessaging_InvalidMarginFraction();
  error L1CoreMessaging_InvalidFundingClampsOrInterestRate();
  error L1CoreMessaging_InvalidMinAmounts();
  error L1CoreMessaging_InvalidMarketLimits();
  error L1CoreMessaging_InvalidCreateOrderParameters();
  error L1CoreMessaging_InvalidShareAmount();
  error L1CoreMessaging_InvalidMarketDataLength();
  error L1CoreMessaging_InvalidConfigPeriod();
  error L1CoreMessaging_InvalidIndexPriceDivider();
  error L1CoreMessaging_InvalidMarginParameters();

  enum MarketStatus {
    NONE,
    ACTIVE
  }

  modifier onlyGovernance() {
    governance.requireGovernor(msg.sender);
    _;
  }

  constructor() {
    l1CoreMessagingImplementation = address(this);
    _disableInitializers();
  }

  /// @notice L1CoreMessaging contract initialization. Can be external because Proxy contract intercepts illegal calls of this function.
  /// @param initializationParameters Encoded representation of initialization parameters:
  /// @dev _zkLighter The address of the ZkLighter proxy
  /// @dev _governance The address of the Governance proxy
  function initialize(bytes calldata initializationParameters) external initializer {
    if (address(this) == l1CoreMessagingImplementation) {
      revert L1CoreMessaging_OnlyProxyCanCallInit();
    }

    __ReentrancyGuard_init();

    (IZkLighterPublic _zkLighter, IGovernance _governance) = abi.decode(initializationParameters, (IZkLighterPublic, IGovernance));
    if (address(_zkLighter) == address(0) || address(_governance) == address(0)) {
      revert L1CoreMessaging_ZeroAddress();
    }
    zkLighter = _zkLighter;
    governance = _governance;
  }

  /// @notice L1CoreMessaging contract upgrade. Can be external because Proxy contract intercepts illegal calls of this function.
  /// @param upgradeParameters Encoded representation of upgrade parameters
  function upgrade(bytes calldata upgradeParameters) external {
    if (address(this) == l1CoreMessagingImplementation) {
      revert L1CoreMessaging_OnlyProxyCanCallUpgrade();
    }
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                         Asset Logic                        */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice Register an asset on Core
  /// @param _params Asset parameters. `indexPriceDivider` must be in [1, MAX_ASSET_EXTENSION_MULTIPLIER] (= type(uint56).max)
  function registerAsset(
    uint8 l1Decimals,
    uint8 l2Decimals,
    uint8 priceDecimals,
    bytes32 symbol,
    TxTypes.RegisterAsset calldata _params
  ) external nonReentrant onlyGovernance {
    ExtendableStorage.AssetConfig memory config = _validateRegisterOnCoreParams(_params);
    bytes memory pubData = TxTypes.writeRegisterAssetPubDataForPriorityQueue({
      assetIndex: _params.assetIndex,
      extensionMultiplier: _params.extensionMultiplier,
      minL2TransferAmount: _params.minL2TransferAmount,
      minL2WithdrawalAmount: _params.minL2WithdrawalAmount,
      marginMode: _params.marginMode,
      loanToValue: _params.loanToValue,
      liquidationThreshold: _params.liquidationThreshold,
      liquidationFactor: _params.liquidationFactor,
      liquidationFee: _params.liquidationFee,
      indexPriceDivider: _params.indexPriceDivider
    });
    bytes memory metadata = TxTypes.writeRegisterAssetPubDataForPriorityQueueWithMetadata(
      pubData,
      l1Decimals,
      l2Decimals,
      priceDecimals,
      config.tickSize,
      config.tokenAddress,
      symbol
    );
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1RegisterAsset, pubData, metadata);
    emit RegisterAsset(_params, l1Decimals, l2Decimals, priceDecimals, symbol);
  }

  /// @notice Update a registered asset on Core
  /// @param _params Asset parameters. `indexPriceDivider` must be in [1, MAX_ASSET_EXTENSION_MULTIPLIER] (= type(uint56).max)
  function updateAsset(TxTypes.UpdateAsset calldata _params) external nonReentrant onlyGovernance {
    if (!_isAssetRegistered(_params.assetIndex)) revert L1CoreMessaging_AssetNotActive();
    if (_params.indexPriceDivider == 0) {
      revert L1CoreMessaging_InvalidIndexPriceDivider();
    }
    _validateCommonAssetParams(
      _params.assetIndex,
      _params.minL2TransferAmount,
      _params.minL2WithdrawalAmount,
      _params.marginMode,
      _params.loanToValue,
      _params.liquidationThreshold,
      _params.liquidationFactor,
      _params.liquidationFee
    );
    bytes memory pubData = TxTypes.writeUpdateAssetPubDataForPriorityQueue({
      assetIndex: _params.assetIndex,
      minL2TransferAmount: _params.minL2TransferAmount,
      minL2WithdrawalAmount: _params.minL2WithdrawalAmount,
      marginMode: _params.marginMode,
      loanToValue: _params.loanToValue,
      liquidationThreshold: _params.liquidationThreshold,
      liquidationFactor: _params.liquidationFactor,
      liquidationFee: _params.liquidationFee,
      indexPriceDivider: _params.indexPriceDivider
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1UpdateAsset, pubData, pubData);
    emit UpdateAsset(_params);
  }

  function _validateRegisterOnCoreParams(TxTypes.RegisterAsset calldata _params) internal view returns (ExtendableStorage.AssetConfig memory config) {
    config = _getAssetConfig(_params.assetIndex);
    if (_params.extensionMultiplier != config.extensionMultiplier) {
      revert L1CoreMessaging_InvalidExtensionMultiplier();
    }
    if (_params.indexPriceDivider == 0) {
      revert L1CoreMessaging_InvalidIndexPriceDivider();
    }
    _validateCommonAssetParams(
      _params.assetIndex,
      _params.minL2TransferAmount,
      _params.minL2WithdrawalAmount,
      _params.marginMode,
      _params.loanToValue,
      _params.liquidationThreshold,
      _params.liquidationFactor,
      _params.liquidationFee
    );
  }

  function _validateCommonAssetParams(
    uint16 assetIndex,
    uint64 minL2TransferAmount,
    uint64 minL2WithdrawalAmount,
    uint8 marginMode,
    uint16 loanToValue,
    uint16 liquidationThreshold,
    uint16 liquidationFactor,
    uint32 liquidationFee
  ) internal pure {
    if (minL2TransferAmount == 0 || minL2TransferAmount > MAX_DEPOSIT_CAP_TICKS) {
      revert L1CoreMessaging_InvalidMinL2TransferAmount();
    }
    if (minL2WithdrawalAmount == 0 || minL2WithdrawalAmount > MAX_DEPOSIT_CAP_TICKS) {
      revert L1CoreMessaging_InvalidMinL2WithdrawalAmount();
    }
    if (marginMode == uint8(TxTypes.AssetMarginMode.Enabled)) {
      if (
        loanToValue == 0 || loanToValue > liquidationThreshold || liquidationThreshold > liquidationFactor || liquidationFactor > ASSET_MARGIN_TICK
      ) {
        revert L1CoreMessaging_InvalidMarginParameters();
      }
      if (liquidationFee + uint32(liquidationFactor) * uint32(FEE_TICK / ASSET_MARGIN_TICK) > FEE_TICK) {
        revert L1CoreMessaging_InvalidMarginParameters();
      }
      if (assetIndex == USDC_ASSET_INDEX && (loanToValue != ASSET_MARGIN_TICK || liquidationFee != 0)) {
        revert L1CoreMessaging_InvalidMarginParameters();
      }
    } else if (marginMode <= uint8(TxTypes.AssetMarginMode.PricedOnly)) {
      // Disabled or PricedOnly
      if (assetIndex == USDC_ASSET_INDEX) {
        revert L1CoreMessaging_InvalidMarginParameters();
      }
      if (loanToValue != 0 || liquidationThreshold != 0 || liquidationFactor != 0 || liquidationFee != 0) {
        revert L1CoreMessaging_InvalidMarginParameters();
      }
    } else {
      revert L1CoreMessaging_InvalidMarginParameters();
    }
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                    Governance Functions                    */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function setSystemConfig(TxTypes.SetSystemConfig calldata _params) external nonReentrant onlyGovernance {
    if (_params.liquidityPoolCooldownPeriod > MAX_CONFIG_PERIOD || _params.stakingPoolLockupPeriod > MAX_CONFIG_PERIOD) {
      revert L1CoreMessaging_InvalidConfigPeriod();
    }
    if (_params.liquidityPoolIndex > MAX_ACCOUNT_INDEX || _params.stakingPoolIndex > MAX_ACCOUNT_INDEX) {
      revert L1CoreMessaging_InvalidAccountIndex();
    }
    _validateMarketFeeParams(_params.maxIntegratorPerpsTakerFee, _params.maxIntegratorPerpsMakerFee);
    _validateMarketFeeParams(_params.maxIntegratorSpotTakerFee, _params.maxIntegratorSpotMakerFee);
    bytes memory priorityRequest = TxTypes.writeSetSystemConfigPubDataForPriorityQueue({
      liquidityPoolIndex: _params.liquidityPoolIndex,
      stakingPoolIndex: _params.stakingPoolIndex,
      liquidityPoolCooldownPeriod: _params.liquidityPoolCooldownPeriod,
      stakingPoolLockupPeriod: _params.stakingPoolLockupPeriod,
      maxIntegratorPerpsTakerFee: _params.maxIntegratorPerpsTakerFee,
      maxIntegratorPerpsMakerFee: _params.maxIntegratorPerpsMakerFee,
      maxIntegratorSpotTakerFee: _params.maxIntegratorSpotTakerFee,
      maxIntegratorSpotMakerFee: _params.maxIntegratorSpotMakerFee
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1SetSystemConfig, priorityRequest, priorityRequest);
    emit SetSystemConfig(_params);
  }

  function _validateMarketFeeParams(uint32 takerFee, uint32 makerFee) private pure {
    if (takerFee > FEE_TICK || makerFee > FEE_TICK) {
      revert L1CoreMessaging_InvalidFeeAmount();
    }
  }

  function createMarket(
    uint8 _size_decimals,
    uint8 _price_decimals,
    bytes32 _symbol,
    TxTypes.CreateMarket calldata _params
  ) external nonReentrant onlyGovernance {
    _validateCreateMarketParams(_params);

    bytes memory priorityRequest = TxTypes.writeCreateMarketPubDataForPriorityQueue({
      marketIndex: _params.marketIndex,
      marketType: _params.marketType,
      marketData: _params.marketData
    });
    bytes memory metadata = TxTypes.writeCreateMarketPubDataForPriorityQueueWithMetadata({
      _data: priorityRequest,
      size_decimals: _size_decimals,
      price_decimals: _price_decimals,
      symbol: _symbol
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1CreateMarket, priorityRequest, metadata);
    emit CreateMarket(_params, _size_decimals, _price_decimals, _symbol);
  }

  function updateMarket(TxTypes.UpdateMarket calldata _params) external nonReentrant onlyGovernance {
    _validateUpdateMarketParams(_params);

    bytes memory pubdata = TxTypes.writeUpdateMarketPubDataForPriorityQueue({
      marketIndex: _params.marketIndex,
      marketType: _params.marketType,
      marketData: _params.marketData
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1UpdateMarket, pubdata, pubdata);
    emit UpdateMarket(_params);
  }

  /// @param _params Market parameters. For spot markets, `sizeExtensionMultiplier` and `quoteExtensionMultiplier` must be
  /// non-zero multiples of FEE_TICK in [FEE_TICK, MAX_ASSET_EXTENSION_MULTIPLIER] (= type(uint56).max)
  function _validateCreateMarketParams(TxTypes.CreateMarket calldata _params) internal view {
    bytes memory _data = _params.marketData;
    if (_params.marketType == TxTypes.MarketType.Perps) {
      if (_params.marketIndex > MAX_PERPS_MARKET_INDEX) revert L1CoreMessaging_InvalidMarketIndex();
      if (_data.length != TxTypes.PACKED_CREATE_MARKET_PERPS_BYTES) {
        revert L1CoreMessaging_InvalidMarketDataLength();
      }
      TxTypes.CreateMarketPerpsData memory perpData = TxTypes.readCreateMarketPerpsData(_data);
      if (perpData.quoteMultiplier == 0 || perpData.quoteMultiplier > MAX_QUOTE_MULTIPLIER) {
        revert L1CoreMessaging_InvalidQuoteMultiplier();
      }
      _validateCommonPerpMarketParams(perpData.common);
    } else if (_params.marketType == TxTypes.MarketType.Spot) {
      if (_params.marketIndex < MIN_SPOT_MARKET_INDEX || _params.marketIndex > MAX_SPOT_MARKET_INDEX) {
        revert L1CoreMessaging_InvalidMarketIndex();
      }
      if (_data.length != TxTypes.PACKED_CREATE_MARKET_SPOT_BYTES) {
        revert L1CoreMessaging_InvalidMarketDataLength();
      }
      TxTypes.CreateMarketSpotData memory spotData = TxTypes.readCreateMarketSpotData(_data);
      if (spotData.baseAssetIndex == spotData.quoteAssetIndex) revert L1CoreMessaging_InvalidMarketAssets();
      if (!_isAssetRegistered(spotData.baseAssetIndex)) revert L1CoreMessaging_InvalidAssetIndex();
      if (!_isAssetRegistered(spotData.quoteAssetIndex)) revert L1CoreMessaging_InvalidAssetIndex();
      if (spotData.sizeExtensionMultiplier == 0 || spotData.sizeExtensionMultiplier % Config.FEE_TICK != 0) {
        revert L1CoreMessaging_InvalidExtensionMultiplier();
      }
      if (spotData.quoteExtensionMultiplier == 0 || spotData.quoteExtensionMultiplier % Config.FEE_TICK != 0) {
        revert L1CoreMessaging_InvalidExtensionMultiplier();
      }
      _validateCommonSpotMarketParams(spotData.common);
    } else {
      revert L1CoreMessaging_InvalidMarketType();
    }
  }

  function _validateUpdateMarketParams(TxTypes.UpdateMarket calldata _params) internal pure {
    bytes memory _data = _params.marketData;
    if (_params.marketType == TxTypes.MarketType.Perps) {
      if (_params.marketIndex > MAX_PERPS_MARKET_INDEX) revert L1CoreMessaging_InvalidMarketIndex();
      if (_data.length != TxTypes.PACKED_UPDATE_MARKET_PERPS_BYTES) {
        revert L1CoreMessaging_InvalidMarketDataLength();
      }
      TxTypes.UpdateMarketPerps memory perpData = TxTypes.readUpdateMarketPerpsData(_data);
      if (perpData.status != uint8(MarketStatus.ACTIVE) && perpData.status != uint8(MarketStatus.NONE)) {
        revert L1CoreMessaging_InvalidMarketStatus();
      }
      _validateCommonPerpMarketParams(perpData.common);
    } else if (_params.marketType == TxTypes.MarketType.Spot) {
      if (_params.marketIndex < MIN_SPOT_MARKET_INDEX || _params.marketIndex > MAX_SPOT_MARKET_INDEX) {
        revert L1CoreMessaging_InvalidMarketIndex();
      }
      if (_data.length != TxTypes.PACKED_UPDATE_MARKET_SPOT_BYTES) {
        revert L1CoreMessaging_InvalidMarketDataLength();
      }
      TxTypes.UpdateMarketSpot memory spotUpdate = TxTypes.readUpdateMarketSpotData(_data);
      if (spotUpdate.status != uint8(MarketStatus.ACTIVE) && spotUpdate.status != uint8(MarketStatus.NONE)) {
        revert L1CoreMessaging_InvalidMarketStatus();
      }
      _validateCommonSpotMarketParams(spotUpdate.common);
    } else {
      revert L1CoreMessaging_InvalidMarketType();
    }
  }

  /// @param p Common perps market parameters. `minBaseAmount` must be in [1, MAX_ORDER_BASE_AMOUNT] (= type(uint48).max);
  /// `minQuoteAmount` and `orderQuoteLimit` must be in [1, MAX_ORDER_QUOTE_AMOUNT] (= type(uint48).max)
  function _validateCommonPerpMarketParams(TxTypes.CommonPerpsData memory p) private pure {
    if (p.takerFee > FEE_TICK || p.makerFee > FEE_TICK || p.liquidationFee > FEE_TICK) {
      revert L1CoreMessaging_InvalidFeeAmount();
    }
    if (
      p.closeOutMarginFraction == 0 ||
      p.closeOutMarginFraction > p.maintenanceMarginFraction ||
      p.maintenanceMarginFraction > p.minInitialMarginFraction ||
      p.minInitialMarginFraction > p.defaultInitialMarginFraction ||
      p.defaultInitialMarginFraction > MARGIN_TICK
    ) revert L1CoreMessaging_InvalidMarginFraction();
    if (p.interestRate > FUNDING_RATE_TICK) revert L1CoreMessaging_InvalidFundingClampsOrInterestRate();
    if (p.fundingClampSmall > FUNDING_RATE_TICK || p.fundingClampBig > FUNDING_RATE_TICK) {
      revert L1CoreMessaging_InvalidFundingClampsOrInterestRate();
    }
    if (p.minBaseAmount == 0 || p.minQuoteAmount == 0) {
      revert L1CoreMessaging_InvalidMinAmounts();
    }
    if (p.minQuoteAmount > p.orderQuoteLimit) {
      revert L1CoreMessaging_InvalidMarketLimits();
    }
    if (p.openInterestLimit < p.orderQuoteLimit || p.openInterestLimit > MAX_MARKET_OPEN_INTEREST) {
      revert L1CoreMessaging_InvalidMarketLimits();
    }
  }

  /// @param p Common spot market parameters. `minBaseAmount` must be in [1, MAX_ORDER_BASE_AMOUNT] (= type(uint48).max);
  /// `minQuoteAmount` and `orderQuoteLimit` must be in [1, MAX_ORDER_QUOTE_AMOUNT] (= type(uint48).max)
  function _validateCommonSpotMarketParams(TxTypes.CommonSpotData memory p) private pure {
    if (p.makerFee > FEE_TICK || p.takerFee > FEE_TICK) {
      revert L1CoreMessaging_InvalidFeeAmount();
    }
    if (p.minBaseAmount == 0 || p.minQuoteAmount == 0) {
      revert L1CoreMessaging_InvalidMinAmounts();
    }
    if (p.minQuoteAmount > p.orderQuoteLimit) {
      revert L1CoreMessaging_InvalidMarketLimits();
    }
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                       User Functions                       */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice Enqueue a withdraw request (reads policy from legacy ZkLighter).
  function withdraw(uint48 _accountIndex, uint16 _assetIndex, TxTypes.RouteType _routeType, uint64 _baseAmount) external nonReentrant {
    if (_accountIndex > MAX_ACCOUNT_INDEX) revert L1CoreMessaging_InvalidAccountIndex();
    ExtendableStorage.AssetConfig memory config = _getAssetConfig(_assetIndex);
    if (config.withdrawalsEnabled == 0) revert L1CoreMessaging_AssetNotActive();
    if (_baseAmount == 0 || _baseAmount > config.depositCapTicks) revert L1CoreMessaging_InvalidWithdrawAmount();

    uint48 _masterAccountIndex = _getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AccountIsNotRegistered();

    bytes memory pubData = TxTypes.writeWithdrawPubDataForPriorityQueue({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      assetIndex: _assetIndex,
      routeType: _routeType,
      baseAmount: _baseAmount
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1Withdraw, pubData, pubData);
    emit Withdraw(_accountIndex, _assetIndex, _routeType, _baseAmount);
  }

  /// @notice Change Lighter public key for an account api key slot
  function changePubKey(uint48 _accountIndex, uint8 _apiKeyIndex, bytes calldata _pubKey) external nonReentrant {
    if (_apiKeyIndex > MAX_API_KEY_INDEX) revert L1CoreMessaging_InvalidApiKeyIndex();

    // Verify that the public key is of the correct length
    if (_pubKey.length != PUB_KEY_BYTES_SIZE) revert L1CoreMessaging_InvalidPubKey();

    // Verify that the public key is in the field
    for (uint256 i = 0; i != 40; i += 8) {
      uint64 elemValue = _readU64LEAt(_pubKey, i);
      if (elemValue >= GOLDILOCKS_MODULUS) revert L1CoreMessaging_InvalidPubKey();
    }

    uint48 _masterAccountIndex = _getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AccountIsNotRegistered();

    if (_accountIndex == NIL_ACCOUNT_INDEX) {
      _accountIndex = _masterAccountIndex;
    }

    bytes memory pubData = TxTypes.writeChangePubKeyPubDataForPriorityQueue({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      apiKeyIndex: _apiKeyIndex,
      pubKey: _pubKey
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1ChangePubKey, pubData, pubData);
    emit ChangePubKey(_accountIndex, _apiKeyIndex, _pubKey);
  }

  /// @dev Reverses the byte order of a 64-bit word (within the low 64 bits).
  /// Assumes `x < 2**64` (i.e., only the lowest 8 bytes may be non-zero).
  function _bswap64(uint256 x) internal pure returns (uint256) {
    // Stage 1: swap adjacent bytes within each 16-bit lane:
    //   [B7 B6 B5 B4 B3 B2 B1 B0] -> [B6 B7 B4 B5 B2 B3 B0 B1]
    x = ((x & 0xFF00FF00FF00FF00) >> 8) | ((x & 0x00FF00FF00FF00FF) << 8);

    // Stage 2: swap 16-bit halves within each 32-bit lane:
    //   [B6 B7 B4 B5 B2 B3 B0 B1] -> [B4 B5 B6 B7 B0 B1 B2 B3]
    x = ((x & 0xFFFF0000FFFF0000) >> 16) | ((x & 0x0000FFFF0000FFFF) << 16);

    // Stage 3: swap 32-bit halves:
    //   [B4 B5 B6 B7 B0 B1 B2 B3] -> [B0 B1 B2 B3 B4 B5 B6 B7]
    x = (x >> 32) | (x << 32);

    // Keep only the low 64 bits (defensive).
    return x & 0xFFFFFFFFFFFFFFFF;
  }

  function _readU64LEAt(bytes calldata data, uint256 o) internal pure returns (uint64 v) {
    uint256 x;
    /// @solidity memory-safe-assembly
    assembly {
      // first 8 bytes at `o` are the top 64 bits of this word
      x := shr(192, calldataload(add(data.offset, o))) // x < 2^64
    }
    x = _bswap64(x);

    // Unsafe cast OK
    v = uint64(x);
  }

  /// @notice Change Lighter public key for an account api key slot
  /// @param _accountIndex Account index for which to change the ECDSA public key. If set to NIL_ACCOUNT_INDEX, the master account index corresponding to the sender will be used.
  /// @param _apiKeyIndex API key slot index
  /// @param _pubKey secp256k1 public key encoded according to the Uncompressed format [0x04 || x || y] specified by ANSI X9.62-1998 standard
  /// @dev All zero bytes [0x00 || 0x00.. || 0x00..] will be interpreted as the "revoked" public key.
  function changeECDSAPubKey(uint48 _accountIndex, uint8 _apiKeyIndex, bytes calldata _pubKey) external nonReentrant {
    if (_apiKeyIndex > MAX_API_KEY_INDEX) revert L1CoreMessaging_InvalidApiKeyIndex();

    // Verify that the public key is of the correct length
    if (_pubKey.length != ECDSA_UNCOMPRESSED_PUB_KEY_BYTES_SIZE) revert L1CoreMessaging_InvalidPubKey();

    bytes memory compressedPubKey = _validateAndCompress(bytes1(_pubKey[0]), bytes32(_pubKey[1:33]), bytes32(_pubKey[33:65]));

    uint48 _masterAccountIndex = _getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AccountIsNotRegistered();

    if (_accountIndex == NIL_ACCOUNT_INDEX) {
      _accountIndex = _masterAccountIndex;
    }

    bytes memory pubData = TxTypes.writeChangeECDSAPubKeyPubDataForPriorityQueue({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      apiKeyIndex: _apiKeyIndex,
      pubKey: compressedPubKey
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1ChangeECDSAPubKey, pubData, pubData);
    emit ChangePubKey(_accountIndex, _apiKeyIndex, compressedPubKey);
  }

  /// @notice Validates a secp256k1 public key and converts to compressed format
  function _validateAndCompress(bytes1 _prefix, bytes32 _x, bytes32 _y) internal pure returns (bytes memory) {
    uint256 x = uint256(_x);
    uint256 y = uint256(_y);

    if (_prefix == 0x00) {
      // All zero bytes will be interpreted as the "revoked" public key.
      if (x != 0 || y != 0) {
        revert L1CoreMessaging_InvalidPubKey();
      }
      return abi.encodePacked(bytes1(uint8(0x02)), _x);
    }

    if (_prefix != 0x04) revert L1CoreMessaging_InvalidPubKey();

    if (x >= SECP256K1_P || y >= SECP256K1_P) revert L1CoreMessaging_InvalidPubKey();

    // y^2 == x^3 + 7 (mod p)
    uint256 lhs = mulmod(y, y, SECP256K1_P);
    uint256 rhs = addmod(mulmod(mulmod(x, x, SECP256K1_P), x, SECP256K1_P), 7, SECP256K1_P);
    if (lhs != rhs) revert L1CoreMessaging_InvalidPubKey();

    return abi.encodePacked(bytes1(uint8(0x02 | (y & 1))), _x);
  }

  /// @notice Cancels all orders
  function cancelAllOrders(uint48 _accountIndex) external nonReentrant {
    if (_accountIndex > MAX_ACCOUNT_INDEX) revert L1CoreMessaging_InvalidAccountIndex();
    uint48 _masterAccountIndex = _getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AccountIsNotRegistered();

    bytes memory pubData = TxTypes.writeCancelAllOrdersPubDataForPriorityQueue({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1CancelAllOrders, pubData, pubData);
    emit CancelAllOrders(_accountIndex);
  }

  /// @notice Create an order for a Lighter account
  /// @param _publicMarketIndex Public market index in [0, MAX_PUBLIC_MARKET_INDEX] (= 2**48 - 1) excluding NIL_PUBLIC_MARKET_INDEX
  /// @param _baseAmount Order base amount in [0, MAX_ORDER_BASE_AMOUNT] (= type(uint48).max); zero defaults to the position size
  /// @param _price Order price in [MIN_ORDER_PRICE, MAX_ORDER_PRICE] (= type(uint32).max)
  function createOrder(
    uint48 _accountIndex,
    uint64 _publicMarketIndex,
    uint48 _baseAmount,
    uint32 _price,
    uint8 _isAsk,
    uint8 _orderType
  ) external nonReentrant {
    if (_accountIndex > MAX_ACCOUNT_INDEX) revert L1CoreMessaging_InvalidAccountIndex();
    uint48 _masterAccountIndex = _getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AccountIsNotRegistered();
    if (_isAsk != 0 && _isAsk != 1) revert L1CoreMessaging_InvalidCreateOrderParameters();
    if (_orderType != uint8(TxTypes.OrderType.LimitOrder) && _orderType != uint8(TxTypes.OrderType.MarketOrder)) {
      revert L1CoreMessaging_InvalidCreateOrderParameters();
    }
    // Zero base amount defaults to the position size, thus is not invalid
    if (_publicMarketIndex > MAX_PUBLIC_MARKET_INDEX || _publicMarketIndex == NIL_PUBLIC_MARKET_INDEX) {
      revert L1CoreMessaging_InvalidMarketIndex();
    }
    if (_price < MIN_ORDER_PRICE) revert L1CoreMessaging_InvalidCreateOrderParameters();

    bytes memory pubData = TxTypes.writeCreateOrderPubDataForPriorityQueue({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      publicMarketIndex: _publicMarketIndex,
      baseAmount: _baseAmount,
      price: _price,
      isAsk: _isAsk,
      orderType: _orderType
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1CreateOrder, pubData, pubData);
    emit CreateOrder(_accountIndex, _masterAccountIndex, _publicMarketIndex, _baseAmount, _price, _isAsk, _orderType);
  }

  /// @notice Burn shares of an account in a public pool
  function burnShares(uint48 _accountIndex, uint48 _publicPoolIndex, uint64 _shareAmount) external nonReentrant {
    if (_accountIndex > MAX_ACCOUNT_INDEX) revert L1CoreMessaging_InvalidAccountIndex();
    if (_accountIndex == _publicPoolIndex) revert L1CoreMessaging_InvalidAccountIndex();
    uint48 _masterAccountIndex = _getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AccountIsNotRegistered();

    if (_publicPoolIndex > MAX_ACCOUNT_INDEX || _publicPoolIndex <= MAX_MASTER_ACCOUNT_INDEX) {
      revert L1CoreMessaging_InvalidAccountIndex();
    }
    if (_shareAmount < MIN_POOL_SHARES_TO_MINT_OR_BURN || _shareAmount > MAX_POOL_SHARES_TO_MINT_OR_BURN) {
      revert L1CoreMessaging_InvalidShareAmount();
    }

    bytes memory pubData = TxTypes.writeBurnSharesPubDataForPriorityQueue({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      publicPoolIndex: _publicPoolIndex,
      sharesAmount: _shareAmount
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1BurnShares, pubData, pubData);
    emit BurnShares(_accountIndex, _masterAccountIndex, _publicPoolIndex, _shareAmount);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                     Internal Helpers                       */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function _getAccountIndexFromAddress(address _address) internal view returns (uint48) {
    uint48 accountIndex = zkLighter.addressToAccountIndex(_address);
    if (accountIndex != 0) return accountIndex;

    if (_address == zkLighter.treasury()) return TREASURY_ACCOUNT_INDEX;
    if (_address == zkLighter.insuranceFundOperator()) return INSURANCE_FUND_OPERATOR_ACCOUNT_INDEX;

    return NIL_ACCOUNT_INDEX;
  }

  function _addPriorityRequest(address sender, uint8 pubdataType, bytes memory priorityRequest, bytes memory pubDataWithMetadata) internal {
    zkLighter.addPriorityRequestExt(sender, pubdataType, priorityRequest, pubDataWithMetadata);
  }

  function _getAssetConfig(uint16 assetIndex) internal view returns (ExtendableStorage.AssetConfig memory config) {
    (
      config.tokenAddress,
      config.withdrawalsEnabled,
      config.extensionMultiplier,
      config.tickSize,
      config.depositCapTicks,
      config.minDepositTicks
    ) = zkLighter.assetConfigs(assetIndex);
    if (assetIndex != NATIVE_ASSET_INDEX && config.tokenAddress == address(0)) {
      revert L1CoreMessaging_InvalidAssetIndex();
    }
  }

  function _isAssetRegistered(uint16 assetIndex) internal view returns (bool) {
    if (assetIndex == NATIVE_ASSET_INDEX) return true;
    (address tokenAddress, , , , , ) = zkLighter.assetConfigs(assetIndex);
    return tokenAddress != address(0);
  }
}
