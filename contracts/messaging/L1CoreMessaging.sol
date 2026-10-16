// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IL1CoreMessaging} from "../interfaces/IL1CoreMessaging.sol";
import {IL1InteropManager} from "../interfaces/IL1InteropManager.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Config} from "../Config.sol";
import {IGovernance} from "../interfaces/IGovernance.sol";
import {IZkLighter} from "../interfaces/IZkLighter.sol";
import {Bytes} from "../lib/Bytes.sol";
import {TxTypes} from "../lib/TxTypes.sol";

/// @notice Core-facing L1 messaging module.
/// @dev Governance and user actions that enqueue Core priority requests live here,
/// and the corresponding events are emitted from this contract.
contract L1CoreMessaging is Initializable, Config, IL1CoreMessaging {
  event Deposit(uint48 toAccountIndex, address toAddress, uint32 assetIndex, TxTypes.RouteType routeType, uint128 baseAmount);
  event ChangePubKey(uint48 accountIndex, uint8 apiKeyIndex, bytes pubKey);
  event CreateMarket(TxTypes.CreateMarket params, uint8 sizeDecimals, uint8 priceDecimals, bytes32 symbol);
  event UpdateAsset(TxTypes.UpdateAsset params);
  event UpdateMarket(TxTypes.UpdateMarket params);
  event CancelAllOrders(uint48 accountIndex);
  event Withdraw(uint48 accountIndex, uint32 assetIndex, TxTypes.RouteType routeType, uint64 baseAmount);
  event CreateOrder(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint16 marketIndex,
    uint48 baseAmount,
    uint32 price,
    uint8 isAsk,
    uint8 orderType
  );
  event BurnShares(uint48 accountIndex, uint48 masterAccountIndex, uint48 publicPoolIndex, uint64 sharesAmount);
  event SendToEvm(uint48 accountIndex, uint32 assetIndex, address evmRecipient, TxTypes.RouteType routeType, uint64 baseAmount);
  event WithdrawToL1Address(uint48 accountIndex, uint32 assetIndex, address l1Recipient, TxTypes.RouteType routeType, uint64 baseAmount);
  event TreasuryUpdate(address newTreasury);
  event InsuranceFundOperatorUpdate(address newInsuranceFundOperator);

  IZkLighter public immutable ZK_LIGHTER;
  IL1InteropManager public immutable INTEROP_MANAGER;

  error L1CoreMessaging_NotInteropManager();
  error L1CoreMessaging_AssetNotActive();
  error L1CoreMessaging_InvalidWithdrawAmount();
  error L1CoreMessaging_ZeroAddress();
  error L1CoreMessaging_AddressInUse();
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
  error L1CoreMessaging_InvalidBaseAmount();
  error L1CoreMessaging_InvalidMarketDataLength();
  error L1CoreMessaging_InvalidConfigPeriod();
  error L1CoreMessaging_InvalidIndexPriceDivider();
  error L1CoreMessaging_InvalidMarginParameters();
  error L1CoreMessaging_InvalidAssetDecimals();

  enum MarketStatus {
    NONE,
    ACTIVE
  }

  struct CoreMessagingStorage {
    uint48 lastAccountIndex;
    uint48 migrationLastAccountIndex;
    mapping(address => uint48) addressToAccountIndex;
    address treasury;
    address insuranceFundOperator;
    IGovernance governance;
  }

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.CoreMessagingStorage")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant CoreMessagingStorageLocation = 0xcaf57d967ca80e4d3bc7f3987fded0e0f0da133b3d06cd48cc48833329419600;

  modifier onlyGovernance() {
    CoreMessagingStorage storage $ = _getCoreMessagingStorage();
    $.governance.requireGovernor(msg.sender);
    _;
  }

  modifier onlyInteropManager() {
    if (msg.sender != address(INTEROP_MANAGER)) revert L1CoreMessaging_NotInteropManager();
    _;
  }

  constructor(IZkLighter _zkLighter, IL1InteropManager _interopManager) {
    _disableInitializers();
    ZK_LIGHTER = _zkLighter;
    INTEROP_MANAGER = _interopManager;
  }

  function upgrade(bytes calldata) external {}

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*               L1InteropManager-Only Functions              */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function registerL1NativeAssetOnCore(
    address sender,
    address l1Address,
    uint8 l1Decimals,
    uint8 coreDecimals,
    uint8 priceDecimals,
    uint56 extensionMultiplier,
    uint128 tickSize,
    bytes32 symbol,
    TxTypes.RegisterAsset calldata _params
  ) external onlyInteropManager {
    _validateRegisterOnCoreParams(_params, coreDecimals, priceDecimals);

    bytes memory pubData = TxTypes.writeRegisterAssetPubDataForPriorityQueue({
      pubdataType: uint8(TxTypes.PriorityPubDataTypeL1RegisterAsset),
      extensionMultiplier: extensionMultiplier,
      coreDecimals: coreDecimals,
      params: _params
    });
    pubData = abi.encodePacked(pubData, l1Address);
    bytes memory metadata = TxTypes.writeRegisterAssetPubDataForPriorityQueueWithMetadata(pubData, l1Decimals, priceDecimals, tickSize, symbol);

    _addPriorityRequest(sender, TxTypes.PriorityPubDataTypeL1RegisterAsset, pubData, metadata);
  }

  function registerEvmNativeAssetOnCore(
    address sender,
    uint8 evmDecimals,
    uint8 coreDecimals,
    uint8 priceDecimals,
    uint56 extensionMultiplier,
    uint128 tickSize,
    bytes32 symbol,
    TxTypes.RegisterAsset calldata _params
  ) external onlyInteropManager {
    _validateRegisterOnCoreParams(_params, coreDecimals, priceDecimals);

    bytes memory pubData = TxTypes.writeRegisterAssetPubDataForPriorityQueue({
      pubdataType: TxTypes.PriorityPubDataTypeL1RegisterEvmNativeAsset,
      extensionMultiplier: extensionMultiplier,
      coreDecimals: coreDecimals,
      params: _params
    });
    bytes memory metadata = abi.encodePacked(pubData, evmDecimals, priceDecimals, tickSize, symbol);

    _addPriorityRequest(sender, TxTypes.PriorityPubDataTypeL1RegisterEvmNativeAsset, pubData, metadata);
  }

  function registerCoreNativeAssetOnCore(
    address sender,
    uint8 coreDecimals,
    uint8 priceDecimals,
    uint56 extensionMultiplier,
    uint128 tickSize,
    bytes32 symbol,
    TxTypes.RegisterAsset calldata _params
  ) external onlyInteropManager {
    _validateRegisterOnCoreParams(_params, coreDecimals, priceDecimals);

    bytes memory pubData = TxTypes.writeRegisterAssetPubDataForPriorityQueue({
      pubdataType: TxTypes.PriorityPubDataTypeL1RegisterCoreNativeAsset,
      extensionMultiplier: extensionMultiplier,
      coreDecimals: coreDecimals,
      params: _params
    });
    bytes memory metadata = abi.encodePacked(pubData, priceDecimals, tickSize, symbol);

    _addPriorityRequest(sender, TxTypes.PriorityPubDataTypeL1RegisterCoreNativeAsset, pubData, metadata);
  }

  function _validateRegisterOnCoreParams(TxTypes.RegisterAsset calldata _params, uint8 coreDecimals, uint8 priceDecimals) internal pure {
    // Core account valuation uses int64 powers of ten, up to 10^18.
    if (coreDecimals > 18) revert L1CoreMessaging_InvalidAssetDecimals();
    // A one-dollar price at this precision must fit in Core's 56-bit index-price field.
    if (priceDecimals > 16) revert L1CoreMessaging_InvalidAssetDecimals();

    if (_params.indexPriceDivider == 0 || _params.indexPriceDivider > MAX_ASSET_EXTENSION_MULTIPLIER) {
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
    uint32 assetIndex,
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
    } else if (marginMode == uint8(TxTypes.AssetMarginMode.Disabled)) {
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

  function registerDeposit(
    address sender,
    address to,
    uint32 assetIndex,
    TxTypes.RouteType routeType,
    uint64 baseAmount
  ) external payable onlyInteropManager {
    CoreMessagingStorage storage $ = _getCoreMessagingStorage();
    uint48 _toAccountIndex = _getAccountIndexFromAddress(to);
    // No account could be found for the address
    if (_toAccountIndex == NIL_ACCOUNT_INDEX) {
      ++$.lastAccountIndex;
      _toAccountIndex = $.lastAccountIndex;
      // The L1-controlled account index range should never be exhausted in practice.
      assert(_toAccountIndex <= MAX_L1_ACCOUNT_INDEX);
      $.addressToAccountIndex[to] = _toAccountIndex;
    }

    // Retain the deposit destination for refunds, including system accounts.
    bytes memory pubData = TxTypes.writeDepositPubDataForPriorityQueue({
      accountIndex: _toAccountIndex,
      toAddress: to,
      assetIndex: assetIndex,
      routeType: routeType,
      baseAmount: baseAmount
    });
    // We avoid using the `_addPriorityRequest` helper here since we want to forward the msg.value.
    ZK_LIGHTER.addPriorityRequestExt{value: msg.value}(sender, TxTypes.PriorityPubDataTypeL1Deposit, pubData, pubData);
    emit Deposit(_toAccountIndex, to, assetIndex, routeType, baseAmount);
  }

  function finalizeEvmWrapperLink(address sender, uint32 assetIndex, address evmWrapper) external onlyInteropManager {
    bytes memory pubData = abi.encodePacked(uint8(TxTypes.PriorityPubDataTypeL1LinkEvmWrapper), assetIndex, evmWrapper);

    _addPriorityRequest(sender, TxTypes.PriorityPubDataTypeL1LinkEvmWrapper, pubData, pubData);
  }

  function finalizeL1WrapperLink(address sender, uint32 assetIndex, address l1Wrapper) external onlyInteropManager {
    bytes memory pubData = abi.encodePacked(uint8(TxTypes.PriorityPubDataTypeL1LinkL1Wrapper), assetIndex, l1Wrapper);

    _addPriorityRequest(sender, TxTypes.PriorityPubDataTypeL1LinkL1Wrapper, pubData, pubData);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                    Governance Functions                    */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function setSystemConfig(TxTypes.SetSystemConfig calldata _params) external onlyGovernance {
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
  }

  function _validateMarketFeeParams(uint32 takerFee, uint32 makerFee) private pure {
    if (takerFee > FEE_TICK || makerFee > FEE_TICK) {
      revert L1CoreMessaging_InvalidFeeAmount();
    }
  }

  function setTreasury(address _newTreasury) external onlyGovernance {
    if (_newTreasury == address(0)) revert L1CoreMessaging_ZeroAddress();
    if (_getAccountIndexFromAddress(_newTreasury) != NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AddressInUse();
    CoreMessagingStorage storage $ = _getCoreMessagingStorage();
    $.treasury = _newTreasury;
    emit TreasuryUpdate(_newTreasury);
  }

  function setInsuranceFundOperator(address _newInsuranceFundOperator) external onlyGovernance {
    if (_newInsuranceFundOperator == address(0)) revert L1CoreMessaging_ZeroAddress();
    if (_getAccountIndexFromAddress(_newInsuranceFundOperator) != NIL_ACCOUNT_INDEX) {
      revert L1CoreMessaging_AddressInUse();
    }
    CoreMessagingStorage storage $ = _getCoreMessagingStorage();
    $.insuranceFundOperator = _newInsuranceFundOperator;
    emit InsuranceFundOperatorUpdate(_newInsuranceFundOperator);
  }

  function updateAsset(TxTypes.UpdateAsset calldata _params) external onlyGovernance {
    if (!_isAssetRegistered(_params.assetIndex)) revert L1CoreMessaging_AssetNotActive();
    if (_params.indexPriceDivider == 0 || _params.indexPriceDivider > MAX_ASSET_EXTENSION_MULTIPLIER) {
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

  function createMarket(uint8 _size_decimals, uint8 _price_decimals, bytes32 _symbol, TxTypes.CreateMarket calldata _params) external onlyGovernance {
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

  function updateMarket(TxTypes.UpdateMarket calldata _params) external onlyGovernance {
    _validateUpdateMarketParams(_params);

    bytes memory pubdata = TxTypes.writeUpdateMarketPubDataForPriorityQueue({
      marketIndex: _params.marketIndex,
      marketType: _params.marketType,
      marketData: _params.marketData
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1UpdateMarket, pubdata, pubdata);
    emit UpdateMarket(_params);
  }

  function _validateCreateMarketParams(TxTypes.CreateMarket calldata _params) internal view {
    bytes calldata _data = _params.marketData;
    if (_params.marketType == TxTypes.MarketType.Perps) {
      if (_params.marketIndex > MAX_PERPS_MARKET_INDEX) revert L1CoreMessaging_InvalidMarketIndex();
      if (_data.length != TxTypes.PACKED_CREATE_MARKET_PERPS_BYTES) {
        revert L1CoreMessaging_InvalidMarketDataLength();
      }
      uint32 quoteMultiplier = Bytes.unsafeReadU32At(_data, 0x00);
      if (quoteMultiplier == 0 || quoteMultiplier > MAX_QUOTE_MULTIPLIER) {
        revert L1CoreMessaging_InvalidQuoteMultiplier();
      }
      _validateCommonPerpMarketParams(_data[4:]);
    } else if (_params.marketType == TxTypes.MarketType.Spot) {
      if (_params.marketIndex < MIN_SPOT_MARKET_INDEX || _params.marketIndex > MAX_SPOT_MARKET_INDEX) {
        revert L1CoreMessaging_InvalidMarketIndex();
      }
      if (_data.length != TxTypes.PACKED_CREATE_MARKET_SPOT_BYTES) {
        revert L1CoreMessaging_InvalidMarketDataLength();
      }
      (
        uint32 baseAssetIndex,
        uint32 quoteAssetIndex,
        uint56 sizeExtensionMultiplier,
        uint56 quoteExtensionMultiplier,
        uint32 takerFee,
        uint32 makerFee,
        uint48 minBaseAmount,
        uint48 minQuoteAmount,
        uint48 orderQuoteLimit
      ) = TxTypes.readCreateMarketSpotData(_data);
      if (baseAssetIndex == quoteAssetIndex) revert L1CoreMessaging_InvalidMarketAssets();
      if (!_isAssetRegistered(baseAssetIndex)) revert L1CoreMessaging_InvalidAssetIndex();
      if (!_isAssetRegistered(quoteAssetIndex)) revert L1CoreMessaging_InvalidAssetIndex();
      if (sizeExtensionMultiplier == 0 || sizeExtensionMultiplier > MAX_ASSET_EXTENSION_MULTIPLIER || sizeExtensionMultiplier % Config.FEE_TICK != 0)
        revert L1CoreMessaging_InvalidExtensionMultiplier();
      if (
        quoteExtensionMultiplier == 0 || quoteExtensionMultiplier > MAX_ASSET_EXTENSION_MULTIPLIER || quoteExtensionMultiplier % Config.FEE_TICK != 0
      ) revert L1CoreMessaging_InvalidExtensionMultiplier();
      _validateCommonSpotMarketParams({
        takerFee: takerFee,
        makerFee: makerFee,
        minBaseAmount: minBaseAmount,
        minQuoteAmount: minQuoteAmount,
        orderQuoteLimit: orderQuoteLimit
      });
    } else {
      revert L1CoreMessaging_InvalidMarketType();
    }
  }

  function _validateUpdateMarketParams(TxTypes.UpdateMarket calldata _params) internal pure {
    bytes calldata _data = _params.marketData;
    if (_params.marketType == TxTypes.MarketType.Perps) {
      if (_params.marketIndex > MAX_PERPS_MARKET_INDEX) revert L1CoreMessaging_InvalidMarketIndex();
      if (_data.length != TxTypes.PACKED_UPDATE_MARKET_PERPS_BYTES) {
        revert L1CoreMessaging_InvalidMarketDataLength();
      }
      uint8 status = Bytes.unsafeReadU8At(_data, 0x00);
      if (status != uint8(MarketStatus.ACTIVE) && status != uint8(MarketStatus.NONE)) {
        revert L1CoreMessaging_InvalidMarketStatus();
      }
      _validateCommonPerpMarketParams(_data[1:]);
    } else if (_params.marketType == TxTypes.MarketType.Spot) {
      if (_params.marketIndex < MIN_SPOT_MARKET_INDEX || _params.marketIndex > MAX_SPOT_MARKET_INDEX) {
        revert L1CoreMessaging_InvalidMarketIndex();
      }
      if (_data.length != TxTypes.PACKED_UPDATE_MARKET_SPOT_BYTES) {
        revert L1CoreMessaging_InvalidMarketDataLength();
      }
      (uint8 status, uint32 takerFee, uint32 makerFee, uint48 minBaseAmount, uint48 minQuoteAmount, uint48 orderQuoteLimit) = TxTypes
        .readUpdateMarketSpotData(_data);
      if (status != uint8(MarketStatus.ACTIVE) && status != uint8(MarketStatus.NONE)) {
        revert L1CoreMessaging_InvalidMarketStatus();
      }
      _validateCommonSpotMarketParams({
        takerFee: takerFee,
        makerFee: makerFee,
        minBaseAmount: minBaseAmount,
        minQuoteAmount: minQuoteAmount,
        orderQuoteLimit: orderQuoteLimit
      });
    } else {
      revert L1CoreMessaging_InvalidMarketType();
    }
  }

  /// @dev Validates common perps fields from packed calldata bytes.
  /// Layout (55 bytes): takerFee(4) | makerFee(4) | liquidationFee(4) | minBaseAmount(6) | minQuoteAmount(6)
  ///   | defaultInitialMarginFraction(2) | minInitialMarginFraction(2) | maintenanceMarginFraction(2)
  ///   | closeOutMarginFraction(2) | interestRate(4) | fundingClampSmall(3) | fundingClampBig(3)
  ///   | openInterestLimit(7) | orderQuoteLimit(6)
  ///
  /// @dev To avoid memory allocation and stack overflow, this function loads
  /// and validates a few fields at a time.
  ///
  /// @dev Data length check deferred to the caller.
  function _validateCommonPerpMarketParams(bytes calldata _data) private pure {
    {
      uint32 takerFee = Bytes.unsafeReadU32At(_data, 0x00);
      uint32 makerFee = Bytes.unsafeReadU32At(_data, 0x04);
      uint32 liquidationFee = Bytes.unsafeReadU32At(_data, 0x08);
      if (makerFee > FEE_TICK || takerFee > FEE_TICK || liquidationFee > FEE_TICK) {
        revert L1CoreMessaging_InvalidFeeAmount();
      }
    }

    {
      uint16 defaultInitialMarginFraction = Bytes.unsafeReadU16At(_data, 0x18);
      uint16 minInitialMarginFraction = Bytes.unsafeReadU16At(_data, 0x1a);
      uint16 maintenanceMarginFraction = Bytes.unsafeReadU16At(_data, 0x1c);
      uint16 closeOutMarginFraction = Bytes.unsafeReadU16At(_data, 0x1e);
      if (
        closeOutMarginFraction == 0 ||
        closeOutMarginFraction > maintenanceMarginFraction ||
        maintenanceMarginFraction > minInitialMarginFraction ||
        minInitialMarginFraction > defaultInitialMarginFraction ||
        defaultInitialMarginFraction > MARGIN_TICK
      ) revert L1CoreMessaging_InvalidMarginFraction();
    }

    {
      uint32 interestRate = Bytes.unsafeReadU32At(_data, 0x20);
      if (interestRate > FUNDING_RATE_TICK) revert L1CoreMessaging_InvalidFundingClampsOrInterestRate();
    }

    {
      uint24 fundingClampSmall = Bytes.unsafeReadU24At(_data, 0x24);
      uint24 fundingClampBig = Bytes.unsafeReadU24At(_data, 0x27);
      if (fundingClampSmall > FUNDING_RATE_TICK || fundingClampBig > FUNDING_RATE_TICK) {
        revert L1CoreMessaging_InvalidFundingClampsOrInterestRate();
      }
    }

    uint48 minQuoteAmount;
    {
      uint48 minBaseAmount = Bytes.unsafeReadU48At(_data, 0x0c);
      minQuoteAmount = Bytes.unsafeReadU48At(_data, 0x12);
      if (minBaseAmount == 0 || minBaseAmount > MAX_ORDER_BASE_AMOUNT || minQuoteAmount == 0 || minQuoteAmount > MAX_ORDER_QUOTE_AMOUNT)
        revert L1CoreMessaging_InvalidMinAmounts();
    }

    {
      uint56 openInterestLimit = Bytes.unsafeReadU56At(_data, 0x2a);
      uint48 orderQuoteLimit = Bytes.unsafeReadU48At(_data, 0x31);
      if (orderQuoteLimit > MAX_ORDER_QUOTE_AMOUNT || minQuoteAmount > orderQuoteLimit) {
        revert L1CoreMessaging_InvalidMarketLimits();
      }
      if (openInterestLimit < orderQuoteLimit || openInterestLimit > MAX_MARKET_OPEN_INTEREST) {
        revert L1CoreMessaging_InvalidMarketLimits();
      }
    }
  }

  /// @dev Validates common spot market fields from stack args.
  function _validateCommonSpotMarketParams(
    uint32 takerFee,
    uint32 makerFee,
    uint48 minBaseAmount,
    uint48 minQuoteAmount,
    uint48 orderQuoteLimit
  ) private pure {
    if (makerFee > FEE_TICK || takerFee > FEE_TICK) {
      revert L1CoreMessaging_InvalidFeeAmount();
    }
    if (minBaseAmount == 0 || minBaseAmount > MAX_ORDER_BASE_AMOUNT || minQuoteAmount == 0 || minQuoteAmount > MAX_ORDER_QUOTE_AMOUNT)
      revert L1CoreMessaging_InvalidMinAmounts();
    if (orderQuoteLimit > MAX_ORDER_QUOTE_AMOUNT || minQuoteAmount > orderQuoteLimit) {
      revert L1CoreMessaging_InvalidMarketLimits();
    }
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                       User Functions                       */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice Enqueue a withdraw request (reads policy from L1InteropManager).
  function withdraw(uint48 _accountIndex, uint32 _assetIndex, TxTypes.RouteType _routeType, uint64 _baseAmount) external {
    if (_accountIndex > MAX_ACCOUNT_INDEX) revert L1CoreMessaging_InvalidAccountIndex();
    if (!_isAssetRegistered(_assetIndex)) revert L1CoreMessaging_AssetNotActive();
    if (_baseAmount == 0 || _baseAmount > MAX_WITHDRAWAL_BASE_AMOUNT) revert L1CoreMessaging_InvalidWithdrawAmount();

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
  function changePubKey(uint48 _accountIndex, uint8 _apiKeyIndex, bytes calldata _pubKey) external {
    if (_accountIndex > MAX_ACCOUNT_INDEX) revert L1CoreMessaging_InvalidAccountIndex();
    if (_apiKeyIndex > MAX_API_KEY_INDEX) revert L1CoreMessaging_InvalidApiKeyIndex();

    // Verify that the public key is of the correct length
    if (_pubKey.length != PUB_KEY_BYTES_SIZE) revert L1CoreMessaging_InvalidPubKey();

    _revertIfPubKeyAllZeros(_pubKey);

    // Verify that the public key is in the field
    for (uint256 i = 0; i != 40; i += 8) {
      uint64 elemValue = _readU64LEAt(_pubKey, i);
      if (elemValue >= GOLDILOCKS_MODULUS) revert L1CoreMessaging_InvalidPubKey();
    }

    uint48 _masterAccountIndex = _getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AccountIsNotRegistered();

    bytes memory pubData = TxTypes.writeChangePubKeyPubDataForPriorityQueue({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      apiKeyIndex: _apiKeyIndex,
      pubKey: _pubKey
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1ChangePubKey, pubData, pubData);
    emit ChangePubKey(_accountIndex, _apiKeyIndex, _pubKey);
  }

  /// @dev Reverts if a 40-byte pubkey is all zeros. Reads two 32-byte words
  /// from calldata; the first covers bytes [0..31], the second [8..39].
  /// If both are zero the entire 40-byte key must be zero.
  ///
  /// @dev Assumes input is a 40-byte payload.
  function _revertIfPubKeyAllZeros(bytes calldata _pubKey) internal pure {
    /// @solidity memory-safe-assembly
    assembly {
      if and(iszero(calldataload(_pubKey.offset)), iszero(calldataload(add(_pubKey.offset, 0x08)))) {
        mstore(0x00, 0xb1a016b7) // L1CoreMessaging_InvalidPubKey()
        revert(0x1c, 0x04)
      }
    }
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

  /// @notice Cancels all orders
  function cancelAllOrders(uint48 _accountIndex) external {
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
  function createOrder(uint48 _accountIndex, uint16 _marketIndex, uint48 _baseAmount, uint32 _price, uint8 _isAsk, uint8 _orderType) external {
    if (_accountIndex > MAX_ACCOUNT_INDEX) revert L1CoreMessaging_InvalidAccountIndex();
    uint48 _masterAccountIndex = _getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AccountIsNotRegistered();
    if (_isAsk != 0 && _isAsk != 1) revert L1CoreMessaging_InvalidCreateOrderParameters();
    if (_orderType != uint8(TxTypes.OrderType.LimitOrder) && _orderType != uint8(TxTypes.OrderType.MarketOrder)) {
      revert L1CoreMessaging_InvalidCreateOrderParameters();
    }
    // Zero base amount defaults to the position size, thus is not invalid
    if (_baseAmount > MAX_ORDER_BASE_AMOUNT) {
      revert L1CoreMessaging_InvalidCreateOrderParameters();
    }
    if (_price > MAX_ORDER_PRICE || _price < MIN_ORDER_PRICE) {
      revert L1CoreMessaging_InvalidCreateOrderParameters();
    }
    if (_marketIndex > MAX_PERPS_MARKET_INDEX) revert L1CoreMessaging_InvalidMarketIndex();

    bytes memory pubData = TxTypes.writeCreateOrderPubDataForPriorityQueue({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      marketIndex: _marketIndex,
      baseAmount: _baseAmount,
      price: _price,
      isAsk: _isAsk,
      orderType: _orderType
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1CreateOrder, pubData, pubData);
    emit CreateOrder(_accountIndex, _masterAccountIndex, _marketIndex, _baseAmount, _price, _isAsk, _orderType);
  }

  /// @notice Burn shares of an account in a public pool
  function burnShares(uint48 _accountIndex, uint48 _publicPoolIndex, uint64 _shareAmount) external {
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

  /// @notice Enqueue a sendToEvm request — debits an asset on Core and credits
  /// the EVM recipient via an exogenous transaction on Lighter EVM. Debit
  /// may target the caller's master or any of its sub-accounts; authorization
  /// is proven by resolving the master from msg.sender.
  function sendToEvm(uint48 _accountIndex, uint32 _assetIndex, address _evmRecipient, TxTypes.RouteType _routeType, uint64 _baseAmount) external {
    if (_accountIndex > MAX_ACCOUNT_INDEX) revert L1CoreMessaging_InvalidAccountIndex();
    if (!_isAssetRegistered(_assetIndex)) revert L1CoreMessaging_AssetNotActive();
    if (_baseAmount == 0) revert L1CoreMessaging_InvalidBaseAmount();
    if (_evmRecipient == address(0)) revert L1CoreMessaging_ZeroAddress();

    uint48 _masterAccountIndex = _getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AccountIsNotRegistered();

    bytes memory pubData = TxTypes.writeSendToEvmPubDataForPriorityQueue({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      assetIndex: _assetIndex,
      evmRecipient: _evmRecipient,
      routeType: _routeType,
      baseAmount: _baseAmount
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1SendToEvm, pubData, pubData);
    emit SendToEvm(_accountIndex, _assetIndex, _evmRecipient, _routeType, _baseAmount);
  }

  /// @notice Enqueue a withdrawToL1Address request — debits an asset on Core and
  /// pays `_l1Recipient` through a Core L1 call. Debit may target the caller's
  /// master or any of its sub-accounts; authorization is proven by resolving the
  /// master from msg.sender. System account role addresses resolve to their own
  /// account index, so the treasury and insurance fund operator withdraw here.
  function withdrawToL1Address(
    uint48 _accountIndex,
    uint32 _assetIndex,
    address _l1Recipient,
    TxTypes.RouteType _routeType,
    uint64 _baseAmount
  ) external {
    if (_accountIndex > MAX_ACCOUNT_INDEX) revert L1CoreMessaging_InvalidAccountIndex();
    if (!_isAssetRegistered(_assetIndex)) revert L1CoreMessaging_AssetNotActive();
    if (_baseAmount == 0 || _baseAmount > MAX_WITHDRAWAL_BASE_AMOUNT) revert L1CoreMessaging_InvalidWithdrawAmount();
    if (_l1Recipient == address(0)) revert L1CoreMessaging_ZeroAddress();

    uint48 _masterAccountIndex = _getAccountIndexFromAddress(msg.sender);
    if (_masterAccountIndex == NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AccountIsNotRegistered();

    bytes memory pubData = TxTypes.writeWithdrawToL1AddressPubDataForPriorityQueue({
      accountIndex: _accountIndex,
      masterAccountIndex: _masterAccountIndex,
      assetIndex: _assetIndex,
      l1Recipient: _l1Recipient,
      routeType: _routeType,
      baseAmount: _baseAmount
    });
    _addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1WithdrawToL1Address, pubData, pubData);
    emit WithdrawToL1Address(_accountIndex, _assetIndex, _l1Recipient, _routeType, _baseAmount);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                     Internal Helpers                       */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function _getCoreMessagingStorage() internal pure returns (CoreMessagingStorage storage $) {
    assembly {
      $.slot := CoreMessagingStorageLocation
    }
  }

  function _getAccountIndexFromAddress(address _address) internal view returns (uint48) {
    CoreMessagingStorage storage $ = _getCoreMessagingStorage();

    // System accounts are sourced from CoreMessaging storage
    if (_address == $.treasury) return TREASURY_ACCOUNT_INDEX;
    if (_address == $.insuranceFundOperator) return INSURANCE_FUND_OPERATOR_ACCOUNT_INDEX;

    // First, check legacy mapping. Legacy accounts must never be shadowed by post-migration mapping.
    uint48 accountIndex = ZK_LIGHTER.addressToAccountIndex(_address);
    if (accountIndex != 0) {
      // Any legacy index must be within the pre-migration boundary. This
      // invariant should never fail.
      assert(accountIndex <= $.migrationLastAccountIndex);
      return accountIndex;
    }

    // Then, check post-migration mapping.
    accountIndex = $.addressToAccountIndex[_address];
    if (accountIndex != 0) return accountIndex;

    return NIL_ACCOUNT_INDEX;
  }

  function _addPriorityRequest(address sender, uint8 pubdataType, bytes memory priorityRequest, bytes memory pubDataWithMetadata) internal {
    ZK_LIGHTER.addPriorityRequestExt(sender, pubdataType, priorityRequest, pubDataWithMetadata);
  }

  function getAccountIndexFromAddress(address _address) external view returns (uint48) {
    return _getAccountIndexFromAddress(_address);
  }

  /// @notice Resolves a system account index to its current address.
  /// Only supports system accounts (treasury, insurance fund).
  /// Reverts for all others.
  function getSystemAddress(uint48 _accountIndex) external view returns (address) {
    CoreMessagingStorage storage $ = _getCoreMessagingStorage();
    if (_accountIndex == TREASURY_ACCOUNT_INDEX) return $.treasury;
    if (_accountIndex == INSURANCE_FUND_OPERATOR_ACCOUNT_INDEX) return $.insuranceFundOperator;
    revert L1CoreMessaging_InvalidAccountIndex();
  }

  function _isAssetRegistered(uint32 assetIndex) internal view returns (bool) {
    return INTEROP_MANAGER.isRegisteredOnL1(assetIndex);
  }
}
