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
    Enabled // 1
  }

  /// @notice Asset destination / source type
  enum RouteType {
    Perps, // 0
    Spot // 1
  }

  /// @notice zklighter priority request types
  uint8 constant PriorityPubDataTypeEmpty = 40;
  uint8 constant PriorityPubDataTypeL1Deposit = 41;
  uint8 constant PriorityPubDataTypeL1ChangePubKey = 42;
  uint8 constant PriorityPubDataTypeL1CreateMarket = 43;
  uint8 constant PriorityPubDataTypeL1UpdateMarket = 44;
  uint8 constant PriorityPubDataTypeL1CancelAllOrders = 45;
  uint8 constant PriorityPubDataTypeL1Withdraw = 46;
  uint8 constant PriorityPubDataTypeL1CreateOrder = 47;
  uint8 constant PriorityPubDataTypeL1BurnShares = 48;
  uint8 constant PriorityPubDataTypeL1RegisterAsset = 49;
  uint8 constant PriorityPubDataTypeL1UpdateAsset = 50;
  uint8 constant PriorityPubDataTypeL1UnstakeAssets = 51;

  /// @notice zklighter onchain transaction types
  enum OnChainPubDataType {
    Empty,
    USDCWithdraw,
    Withdraw
  }

  uint32 internal constant USDCWithdrawLogSize = 15; // 1 byte for type, 6 bytes for accountIndex, 8 bytes for usdcAmount
  uint32 internal constant WithdrawLogSize = 17; // 1 byte for type, 2 bytes for assetIndex, 6 bytes for accountIndex, 8 bytes for amount

  enum OrderType {
    LimitOrder,
    MarketOrder
  }

  uint256 internal constant DEPOSIT_PUB_DATA_SIZE = 38;

  struct Deposit {
    uint48 accountIndex;
    address toAddress;
    uint16 assetIndex;
    RouteType routeType;
    uint64 baseAmount;
  }

  /// @notice Serialize deposit pubData
  function writeDepositPubDataForPriorityQueue(Deposit memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1Deposit), _tx.accountIndex, _tx.toAddress, _tx.assetIndex, _tx.routeType, _tx.baseAmount);
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

  struct L1Withdraw {
    uint48 accountIndex;
    uint48 masterAccountIndex;
    uint16 assetIndex;
    RouteType routeType;
    uint64 baseAmount;
  }

  /// @notice Serialize withdraw pubData
  function writeWithdrawPubDataForPriorityQueue(L1Withdraw memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(
      uint8(PriorityPubDataTypeL1Withdraw),
      _tx.accountIndex,
      _tx.masterAccountIndex,
      _tx.assetIndex,
      _tx.routeType,
      _tx.baseAmount
    );
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
  function writeCreateMarketPubDataForPriorityQueue(CreateMarket memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1CreateMarket), _tx.marketIndex, _tx.marketType, _tx.marketData);
  }

  /// @notice Serialize create order book pubData, includes metadata
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
  function writeUpdateMarketPubDataForPriorityQueue(UpdateMarket memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1UpdateMarket), _tx.marketIndex, _tx.marketType, _tx.marketData);
  }

  struct CreateOrder {
    uint48 accountIndex;
    uint48 masterAccountIndex;
    uint16 marketIndex;
    uint48 baseAmount;
    uint32 price;
    uint8 isAsk;
    uint8 orderType;
  }

  /// @notice Serialize create order pubData
  function writeCreateOrderPubDataForPriorityQueue(CreateOrder memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(
      uint8(PriorityPubDataTypeL1CreateOrder),
      _tx.accountIndex,
      _tx.masterAccountIndex,
      _tx.marketIndex,
      _tx.baseAmount,
      _tx.price,
      _tx.isAsk,
      _tx.orderType
    );
  }

  struct BurnShares {
    uint48 accountIndex;
    uint48 masterAccountIndex;
    uint48 publicPoolIndex;
    uint64 sharesAmount;
  }

  /// @notice Serialize burn shares pubData
  function writeBurnSharesPubDataForPriorityQueue(BurnShares memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1BurnShares), _tx.accountIndex, _tx.masterAccountIndex, _tx.publicPoolIndex, _tx.sharesAmount);
  }

  struct CancelAllOrders {
    uint48 accountIndex;
    uint48 masterAccountIndex;
  }

  /// @notice Serialize cancel all orders pubData
  function writeCancelAllOrdersPubDataForPriorityQueue(CancelAllOrders memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1CancelAllOrders), _tx.accountIndex, _tx.masterAccountIndex);
  }

  struct ChangePubKey {
    uint48 accountIndex;
    uint48 masterAccountIndex;
    uint8 apiKeyIndex;
    bytes pubKey;
  }

  /// @notice Serialize change pub key pubData
  function writeChangePubKeyPubDataForPriorityQueue(ChangePubKey memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1ChangePubKey), _tx.accountIndex, _tx.masterAccountIndex, _tx.apiKeyIndex, _tx.pubKey);
  }

  struct RegisterAsset {
    uint16 assetIndex; // Asset index of the token being registered
    uint56 extensionMultiplier; // Lighter internal asset extension multiplier
    uint64 minL2TransferAmount; // Minimum L2 transfer amount for the asset
    uint64 minL2WithdrawalAmount; // Minimum L2 withdrawal amount for the asset
    uint8 marginMode; // 0 if disabled, 1 if enabled
  }

  /// @notice Serialize create asset pubData
  function writeRegisterAssetPubDataForPriorityQueue(RegisterAsset memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(
      uint8(PriorityPubDataTypeL1RegisterAsset),
      _tx.assetIndex,
      _tx.extensionMultiplier,
      _tx.minL2TransferAmount,
      _tx.minL2WithdrawalAmount,
      _tx.marginMode
    );
  }

  /// @notice Serialize create order book pubData, includes metadata
  function writeRegisterAssetPubDataForPriorityQueueWithMetadata(
    bytes memory _data,
    uint8 l1Decimals,
    uint8 decimals,
    uint128 tickSize,
    address tokenAddress,
    bytes32 symbol
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(_data, l1Decimals, decimals, tickSize, tokenAddress, symbol);
  }

  struct UpdateAsset {
    uint16 assetIndex; // Asset index of the token being updated
    uint64 minL2TransferAmount; // Minimum L2 transfer amount for the asset
    uint64 minL2WithdrawalAmount; // Minimum L2 withdrawal amount for the asset
    uint8 marginMode; // 0 if disabled, 1 if enabled
  }

  /// @notice Serialize update asset pubData
  function writeUpdateAssetPubDataForPriorityQueue(UpdateAsset memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(
      uint8(PriorityPubDataTypeL1UpdateAsset),
      _tx.assetIndex,
      _tx.minL2TransferAmount,
      _tx.minL2WithdrawalAmount,
      _tx.marginMode
    );
  }

  struct UnstakeAssets {
    uint48 accountIndex;
    uint48 masterAccountIndex;
    uint48 stakingPoolIndex;
    uint64 sharesAmount;
  }

  /// @notice Serialize update asset pubData
  function writeUnstakeAssetsPubDataForPriorityQueue(UnstakeAssets memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(
      uint8(PriorityPubDataTypeL1UnstakeAssets),
      _tx.accountIndex,
      _tx.masterAccountIndex,
      _tx.stakingPoolIndex,
      _tx.sharesAmount
    );
  }
}
