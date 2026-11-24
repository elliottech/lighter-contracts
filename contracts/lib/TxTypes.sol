// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "./Bytes.sol";

/// @title zkLighter TxTypes Library
/// @notice Implements helper functions to serialize and deserialize tx types
/// @author zkLighter Team
library TxTypes {
  /// @notice Market types
  enum MarketType {
    Perps, // 0
    Spot // 1
  }

  /// @notice Asset margin modes
  enum AssetMarginMode {
    Disabled, // 0
    Enabled, // 1
    PricedOnly // 2
  }

  /// @notice Asset destination / source type
  enum RouteType {
    Perps, // 0
    Spot // 1
  }

  /// @notice zklighter priority request types
  uint8 constant PriorityPubDataTypeEmpty = 60;
  uint8 constant PriorityPubDataTypeL1Deposit = 61;
  uint8 constant PriorityPubDataTypeL1ChangePubKey = 62;
  uint8 constant PriorityPubDataTypeL1CreateMarket = 63;
  uint8 constant PriorityPubDataTypeL1UpdateMarket = 64;
  uint8 constant PriorityPubDataTypeL1CancelAllOrders = 65;
  uint8 constant PriorityPubDataTypeL1Withdraw = 66;
  uint8 constant PriorityPubDataTypeL1CreateOrder = 67;
  uint8 constant PriorityPubDataTypeL1BurnShares = 68;
  uint8 constant PriorityPubDataTypeL1RegisterAsset = 69;
  uint8 constant PriorityPubDataTypeL1UpdateAsset = 70;
  uint8 constant PriorityPubDataTypeL1UnstakeAssets = 71;
  uint8 constant PriorityPubDataTypeL1SetSystemConfig = 72;
  uint8 constant PriorityPubDataTypeL1ChangeECDSAPubKey = 73;

  /// @notice zklighter onchain transaction types
  enum OnChainPubDataType {
    Empty,
    USDCWithdraw,
    Withdraw
  }

  uint32 internal constant USDCWithdrawLogSize = 15; // 1 byte for type, 6 bytes for accountIndex, 8 bytes for usdcAmount
  uint32 internal constant WithdrawLogSize = 17; // 1 byte for type, 6 bytes for masterAccountIndex, 2 bytes for assetIndex, 8 bytes for baseAmount

  enum OrderType {
    LimitOrder,
    MarketOrder
  }

  uint256 internal constant DEPOSIT_PUB_DATA_SIZE = 38;

  /// @notice Serialize deposit pubData
  /// Layout: type(1) | accountIndex(6) | toAddress(20) | assetIndex(2) | routeType(1) | baseAmount(8) = 38 bytes
  function writeDepositPubDataForPriorityQueue(
    uint48 accountIndex,
    address toAddress,
    uint16 assetIndex,
    RouteType routeType,
    uint64 baseAmount
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1Deposit), accountIndex, toAddress, assetIndex, routeType, baseAmount);
  }

  /// @notice Deserialize deposit pubData
  function readDepositForDesertMode(bytes memory _data) internal pure returns (uint48 accountIndex, uint16 assetIndex, uint64 baseAmount) {
    uint256 _offset = 1; // Skipping the tx type
    (_offset, accountIndex) = Bytes.readUInt48(_data, _offset);
    _offset += 20; // Skipping the address
    (_offset, assetIndex) = Bytes.readUInt16(_data, _offset);
    _offset++; // Skipping the route type
    (_offset, baseAmount) = Bytes.readUInt64(_data, _offset);
    return (accountIndex, assetIndex, baseAmount);
  }

  /// @notice Serialize withdraw pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) | assetIndex(2) | routeType(1) | baseAmount(8) = 24 bytes
  function writeWithdrawPubDataForPriorityQueue(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint16 assetIndex,
    RouteType routeType,
    uint64 baseAmount
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1Withdraw), accountIndex, masterAccountIndex, assetIndex, routeType, baseAmount);
  }

  struct Withdraw {
    uint48 masterAccountIndex;
    uint16 assetIndex;
    uint64 baseAmount;
  }

  /// @notice Deserialize withdraw pubData
  function readWithdrawOnChainLog(bytes memory _data, uint256 _offset) internal pure returns (Withdraw memory parsed, uint256 newOffset) {
    _offset++; // Skipping the type
    (_offset, parsed.masterAccountIndex) = Bytes.readUInt48(_data, _offset);
    (_offset, parsed.assetIndex) = Bytes.readUInt16(_data, _offset);
    (_offset, parsed.baseAmount) = Bytes.readUInt64(_data, _offset);
    return (parsed, _offset);
  }

  struct USDCWithdraw {
    uint48 masterAccountIndex;
    uint64 usdcAmount;
  }

  /// @notice Deserialize USDC withdraw pubData
  function readUSDCWithdrawOnChainLog(bytes memory _data, uint256 _offset) internal pure returns (USDCWithdraw memory parsed, uint256 newOffset) {
    _offset++; // Skipping the type
    (_offset, parsed.masterAccountIndex) = Bytes.readUInt48(_data, _offset);
    (_offset, parsed.usdcAmount) = Bytes.readUInt64(_data, _offset);
    return (parsed, _offset);
  }

  uint8 internal constant PACKED_COMMON_PERPS_DATA_BYTES = 55;

  struct CommonPerpsData {
    uint32 takerFee;
    uint32 makerFee;
    uint32 liquidationFee;
    uint48 minBaseAmount;
    uint48 minQuoteAmount;
    uint16 defaultInitialMarginFraction;
    uint16 minInitialMarginFraction;
    uint16 maintenanceMarginFraction;
    uint16 closeOutMarginFraction;
    uint32 interestRate;
    uint24 fundingClampSmall;
    uint24 fundingClampBig;
    uint56 openInterestLimit;
    uint48 orderQuoteLimit;
  }

  uint8 internal constant PACKED_CREATE_MARKET_PERPS_BYTES = 4 + PACKED_COMMON_PERPS_DATA_BYTES;

  struct CreateMarketPerpsData {
    uint32 quoteMultiplier;
    CommonPerpsData common;
  }

  function readCreateMarketPerpsData(bytes memory _data) internal pure returns (CreateMarketPerpsData memory parsed) {
    if (_data.length != PACKED_CREATE_MARKET_PERPS_BYTES) {
      revert("Invalid packed create market perps data length");
    }
    uint256 _offset;
    (_offset, parsed.quoteMultiplier) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.takerFee) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.makerFee) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.liquidationFee) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.minBaseAmount) = Bytes.readUInt48(_data, _offset);
    (_offset, parsed.common.minQuoteAmount) = Bytes.readUInt48(_data, _offset);
    (_offset, parsed.common.defaultInitialMarginFraction) = Bytes.readUInt16(_data, _offset);
    (_offset, parsed.common.minInitialMarginFraction) = Bytes.readUInt16(_data, _offset);
    (_offset, parsed.common.maintenanceMarginFraction) = Bytes.readUInt16(_data, _offset);
    (_offset, parsed.common.closeOutMarginFraction) = Bytes.readUInt16(_data, _offset);
    (_offset, parsed.common.interestRate) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.fundingClampSmall) = Bytes.readUInt24(_data, _offset);
    (_offset, parsed.common.fundingClampBig) = Bytes.readUInt24(_data, _offset);
    (_offset, parsed.common.openInterestLimit) = Bytes.readUInt56(_data, _offset);
    (_offset, parsed.common.orderQuoteLimit) = Bytes.readUInt48(_data, _offset);
    return parsed;
  }

  uint8 internal constant PACKED_COMMON_SPOT_DATA_BYTES = 26;

  struct CommonSpotData {
    uint32 takerFee;
    uint32 makerFee;
    uint48 minBaseAmount;
    uint48 minQuoteAmount;
    uint48 orderQuoteLimit;
  }

  uint8 internal constant PACKED_CREATE_MARKET_SPOT_BYTES = 18 + PACKED_COMMON_SPOT_DATA_BYTES;

  struct CreateMarketSpotData {
    uint16 baseAssetIndex;
    uint16 quoteAssetIndex;
    uint56 sizeExtensionMultiplier;
    uint56 quoteExtensionMultiplier;
    CommonSpotData common;
  }

  function readCreateMarketSpotData(bytes memory _data) internal pure returns (CreateMarketSpotData memory parsed) {
    if (_data.length != PACKED_CREATE_MARKET_SPOT_BYTES) {
      revert("Invalid packed create market spot data length");
    }
    uint256 _offset;
    (_offset, parsed.baseAssetIndex) = Bytes.readUInt16(_data, _offset);
    (_offset, parsed.quoteAssetIndex) = Bytes.readUInt16(_data, _offset);
    (_offset, parsed.sizeExtensionMultiplier) = Bytes.readUInt56(_data, _offset);
    (_offset, parsed.quoteExtensionMultiplier) = Bytes.readUInt56(_data, _offset);
    (_offset, parsed.common.takerFee) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.makerFee) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.minBaseAmount) = Bytes.readUInt48(_data, _offset);
    (_offset, parsed.common.minQuoteAmount) = Bytes.readUInt48(_data, _offset);
    (_offset, parsed.common.orderQuoteLimit) = Bytes.readUInt48(_data, _offset);
    return parsed;
  }

  struct CreateMarket {
    uint16 marketIndex;
    MarketType marketType;
    bytes marketData;
  }

  /// @notice Serialize create order book pubData, it does not include metadata
  /// Layout: type(1) | marketIndex(2) | marketType(1) | marketData(N) = 4+N bytes
  function writeCreateMarketPubDataForPriorityQueue(
    uint16 marketIndex,
    MarketType marketType,
    bytes memory marketData
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1CreateMarket), marketIndex, marketType, marketData);
  }

  /// @notice Serialize create order book pubData, includes metadata
  /// Layout: _data(N) | size_decimals(1) | price_decimals(1) | symbol(32) = N+34 bytes
  function writeCreateMarketPubDataForPriorityQueueWithMetadata(
    bytes memory _data,
    uint8 size_decimals,
    uint8 price_decimals,
    bytes32 symbol
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(_data, size_decimals, price_decimals, symbol);
  }

  struct UpdateMarket {
    uint16 marketIndex;
    MarketType marketType;
    bytes marketData;
  }

  uint8 internal constant PACKED_UPDATE_MARKET_PERPS_BYTES = 1 + PACKED_COMMON_PERPS_DATA_BYTES;

  struct UpdateMarketPerps {
    uint8 status;
    CommonPerpsData common;
  }

  function readUpdateMarketPerpsData(bytes memory _data) internal pure returns (UpdateMarketPerps memory parsed) {
    if (_data.length != PACKED_UPDATE_MARKET_PERPS_BYTES) {
      revert("Invalid packed update market perps data length");
    }
    uint256 _offset;
    (_offset, parsed.status) = Bytes.readUInt8(_data, _offset);
    (_offset, parsed.common.takerFee) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.makerFee) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.liquidationFee) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.minBaseAmount) = Bytes.readUInt48(_data, _offset);
    (_offset, parsed.common.minQuoteAmount) = Bytes.readUInt48(_data, _offset);
    (_offset, parsed.common.defaultInitialMarginFraction) = Bytes.readUInt16(_data, _offset);
    (_offset, parsed.common.minInitialMarginFraction) = Bytes.readUInt16(_data, _offset);
    (_offset, parsed.common.maintenanceMarginFraction) = Bytes.readUInt16(_data, _offset);
    (_offset, parsed.common.closeOutMarginFraction) = Bytes.readUInt16(_data, _offset);
    (_offset, parsed.common.interestRate) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.fundingClampSmall) = Bytes.readUInt24(_data, _offset);
    (_offset, parsed.common.fundingClampBig) = Bytes.readUInt24(_data, _offset);
    (_offset, parsed.common.openInterestLimit) = Bytes.readUInt56(_data, _offset);
    (_offset, parsed.common.orderQuoteLimit) = Bytes.readUInt48(_data, _offset);
    return parsed;
  }

  uint8 internal constant PACKED_UPDATE_MARKET_SPOT_BYTES = 1 + PACKED_COMMON_SPOT_DATA_BYTES;

  struct UpdateMarketSpot {
    uint8 status;
    CommonSpotData common;
  }

  function readUpdateMarketSpotData(bytes memory _data) internal pure returns (UpdateMarketSpot memory parsed) {
    if (_data.length != PACKED_UPDATE_MARKET_SPOT_BYTES) {
      revert("Invalid packed update market spot data length");
    }
    uint256 _offset;
    (_offset, parsed.status) = Bytes.readUInt8(_data, _offset);
    (_offset, parsed.common.takerFee) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.makerFee) = Bytes.readUInt32(_data, _offset);
    (_offset, parsed.common.minBaseAmount) = Bytes.readUInt48(_data, _offset);
    (_offset, parsed.common.minQuoteAmount) = Bytes.readUInt48(_data, _offset);
    (_offset, parsed.common.orderQuoteLimit) = Bytes.readUInt48(_data, _offset);
    return parsed;
  }

  /// @notice Serialize update order book pubData
  /// Layout: type(1) | marketIndex(2) | marketType(1) | marketData(N) = 4+N bytes
  function writeUpdateMarketPubDataForPriorityQueue(
    uint16 marketIndex,
    MarketType marketType,
    bytes memory marketData
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1UpdateMarket), marketIndex, marketType, marketData);
  }

  /// @notice Serialize create order pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) | publicMarketIndex(8) | baseAmount(6) | price(4) | isAsk(1) | orderType(1) = 33 bytes
  function writeCreateOrderPubDataForPriorityQueue(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint64 publicMarketIndex,
    uint48 baseAmount,
    uint32 price,
    uint8 isAsk,
    uint8 orderType
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(
      uint8(PriorityPubDataTypeL1CreateOrder),
      accountIndex,
      masterAccountIndex,
      publicMarketIndex,
      baseAmount,
      price,
      isAsk,
      orderType
    );
  }

  /// @notice Serialize burn shares pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) | publicPoolIndex(6) | sharesAmount(8) = 27 bytes
  function writeBurnSharesPubDataForPriorityQueue(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint48 publicPoolIndex,
    uint64 sharesAmount
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1BurnShares), accountIndex, masterAccountIndex, publicPoolIndex, sharesAmount);
  }

  /// @notice Serialize cancel all orders pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) = 13 bytes
  function writeCancelAllOrdersPubDataForPriorityQueue(uint48 accountIndex, uint48 masterAccountIndex) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1CancelAllOrders), accountIndex, masterAccountIndex);
  }

  /// @notice Serialize change pub key pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) | apiKeyIndex(1) | pubKey(40) = 54 bytes
  function writeChangePubKeyPubDataForPriorityQueue(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint8 apiKeyIndex,
    bytes memory pubKey
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1ChangePubKey), accountIndex, masterAccountIndex, apiKeyIndex, pubKey);
  }

  /// @notice Serialize change pub key pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) | apiKeyIndex(1) | pubKey(33) = 47 bytes
  function writeChangeECDSAPubKeyPubDataForPriorityQueue(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint8 apiKeyIndex,
    bytes memory pubKey
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1ChangeECDSAPubKey), accountIndex, masterAccountIndex, apiKeyIndex, pubKey);
  }

  struct SetSystemConfig {
    uint48 liquidityPoolIndex;
    uint48 stakingPoolIndex;
    uint48 liquidityPoolCooldownPeriod;
    uint48 stakingPoolLockupPeriod;
    uint32 maxIntegratorPerpsTakerFee;
    uint32 maxIntegratorPerpsMakerFee;
    uint32 maxIntegratorSpotTakerFee;
    uint32 maxIntegratorSpotMakerFee;
  }

  /// @notice Serialize set system config pubData
  function writeSetSystemConfigPubDataForPriorityQueue(
    uint48 liquidityPoolIndex,
    uint48 stakingPoolIndex,
    uint48 liquidityPoolCooldownPeriod,
    uint48 stakingPoolLockupPeriod,
    uint32 maxIntegratorPerpsTakerFee,
    uint32 maxIntegratorPerpsMakerFee,
    uint32 maxIntegratorSpotTakerFee,
    uint32 maxIntegratorSpotMakerFee
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(
      uint8(PriorityPubDataTypeL1SetSystemConfig),
      liquidityPoolIndex,
      stakingPoolIndex,
      liquidityPoolCooldownPeriod,
      stakingPoolLockupPeriod,
      maxIntegratorPerpsTakerFee,
      maxIntegratorPerpsMakerFee,
      maxIntegratorSpotTakerFee,
      maxIntegratorSpotMakerFee
    );
  }

  struct RegisterAsset {
    uint16 assetIndex; // Asset index of the token being registered
    uint56 extensionMultiplier; // Lighter internal asset extension multiplier
    uint64 minL2TransferAmount; // Minimum L2 transfer amount for the asset
    uint64 minL2WithdrawalAmount; // Minimum L2 withdrawal amount for the asset
    uint8 marginMode; // 0 if disabled, 1 if enabled
    uint16 loanToValue;
    uint16 liquidationThreshold;
    uint16 liquidationFactor;
    uint32 liquidationFee;
    uint56 indexPriceDivider; // Extended asset balance * index price / indexPriceDivider = extended USDC value
  }

  /// @notice Serialize register asset pubData with the richer legacy asset parameters
  function writeRegisterAssetPubDataForPriorityQueue(
    uint16 assetIndex,
    uint56 extensionMultiplier,
    uint64 minL2TransferAmount,
    uint64 minL2WithdrawalAmount,
    uint8 marginMode,
    uint16 loanToValue,
    uint16 liquidationThreshold,
    uint16 liquidationFactor,
    uint32 liquidationFee,
    uint56 indexPriceDivider
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(
      uint8(PriorityPubDataTypeL1RegisterAsset),
      assetIndex,
      extensionMultiplier,
      minL2TransferAmount,
      minL2WithdrawalAmount,
      marginMode,
      loanToValue,
      liquidationThreshold,
      liquidationFactor,
      liquidationFee,
      indexPriceDivider
    );
  }

  /// @notice Serialize register asset pubData with the richer legacy metadata
  function writeRegisterAssetPubDataForPriorityQueueWithMetadata(
    bytes memory _data,
    uint8 l1Decimals,
    uint8 l2Decimals,
    uint8 priceDecimals,
    uint128 tickSize,
    address tokenAddress,
    bytes32 symbol
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(_data, l1Decimals, l2Decimals, priceDecimals, tickSize, tokenAddress, symbol);
  }

  struct UpdateAsset {
    uint16 assetIndex; // Asset index of the token being updated
    uint64 minL2TransferAmount; // Minimum L2 transfer amount for the asset
    uint64 minL2WithdrawalAmount; // Minimum L2 withdrawal amount for the asset
    uint8 marginMode; // 0 if disabled, 1 if enabled
    uint16 loanToValue;
    uint16 liquidationThreshold;
    uint16 liquidationFactor;
    uint32 liquidationFee;
    uint56 indexPriceDivider; // Extended asset balance * index price / indexPriceDivider = extended USDC value
  }

  /// @notice Serialize update asset pubData
  function writeUpdateAssetPubDataForPriorityQueue(
    uint16 assetIndex,
    uint64 minL2TransferAmount,
    uint64 minL2WithdrawalAmount,
    uint8 marginMode,
    uint16 loanToValue,
    uint16 liquidationThreshold,
    uint16 liquidationFactor,
    uint32 liquidationFee,
    uint56 indexPriceDivider
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(
      uint8(PriorityPubDataTypeL1UpdateAsset),
      assetIndex,
      minL2TransferAmount,
      minL2WithdrawalAmount,
      marginMode,
      loanToValue,
      liquidationThreshold,
      liquidationFactor,
      liquidationFee,
      indexPriceDivider
    );
  }
}
