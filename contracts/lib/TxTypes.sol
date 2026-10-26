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
  uint8 constant PriorityPubDataTypeL1SetSystemConfig = 52;
  uint8 constant PriorityPubDataTypeL1RegisterCoreNativeAsset = 53;
  uint8 constant PriorityPubDataTypeL1RegisterEvmNativeAsset = 54;
  uint8 constant PriorityPubDataTypeL1LinkEvmWrapper = 55;
  uint8 constant PriorityPubDataTypeL1LinkL1Wrapper = 56;
  uint8 constant PriorityPubDataTypeL1SendToEvm = 128;
  uint8 constant PriorityPubDataTypeL1WithdrawToL1Address = 129;

  /// @notice zklighter onchain transaction types
  enum OnChainPubDataType {
    Empty,
    USDCWithdraw,
    Withdraw,
    L1Call
  }

  uint32 internal constant L1CallLogSize = 33; // 1 byte for type, 32 for L1 call hash

  enum OrderType {
    LimitOrder,
    MarketOrder
  }

  uint256 internal constant DEPOSIT_PUB_DATA_SIZE = 40;

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                    L1 TO CORE MESSAGES                     */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice Serialize deposit pubData
  /// Layout: type(1) | accountIndex(6) | toAddress(20) | assetIndex(4) | routeType(1) | baseAmount(8) = 40 bytes
  /// @param routeType Caller must provide an in-bounds RouteType enum value.
  function writeDepositPubDataForPriorityQueue(
    uint48 accountIndex,
    address toAddress,
    uint32 assetIndex,
    RouteType routeType,
    uint64 baseAmount
  ) internal pure returns (bytes memory buf) {
    assembly {
      buf := mload(0x40)
      mstore(buf, 0x28)
      let ptr := add(buf, 0x20)
      mstore8(ptr, PriorityPubDataTypeL1Deposit)
      mstore(add(ptr, 0x01), shl(0xd0, accountIndex))
      mstore(add(ptr, 0x07), shl(0x60, toAddress))
      mstore(add(ptr, 0x1b), shl(0xe0, assetIndex))
      mstore(add(ptr, 0x1f), shl(0xf8, routeType))
      mstore(add(ptr, 0x20), shl(0xc0, baseAmount))
      mstore(0x40, add(buf, 0x48))
    }
  }

  /// @notice Read deposit fields from calldata for desert mode cancellation
  /// Layout: type(1) | accountIndex(6) | toAddress(20) | assetIndex(4) | routeType(1) | baseAmount(8)
  function readDepositFromCalldata(
    bytes calldata _data
  ) internal pure returns (uint48 accountIndex, address toAddress, uint32 assetIndex, uint64 baseAmount) {
    accountIndex = Bytes.unsafeReadU48At(_data, 0x01);
    toAddress = Bytes.unsafeReadAddressAt(_data, 0x07);
    assetIndex = Bytes.unsafeReadU32At(_data, 0x1b);
    baseAmount = Bytes.unsafeReadU64At(_data, 0x20);
  }

  /// @notice Serialize withdraw pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) | assetIndex(4) | routeType(1) | baseAmount(8) = 26 bytes
  /// @param routeType Caller must provide an in-bounds RouteType enum value.
  function writeWithdrawPubDataForPriorityQueue(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint32 assetIndex,
    RouteType routeType,
    uint64 baseAmount
  ) internal pure returns (bytes memory buf) {
    assembly {
      buf := mload(0x40)
      mstore(buf, 0x1a)
      let ptr := add(buf, 0x20)
      mstore8(ptr, PriorityPubDataTypeL1Withdraw)
      mstore(add(ptr, 0x01), shl(0xd0, accountIndex))
      mstore(add(ptr, 0x07), shl(0xd0, masterAccountIndex))
      mstore(add(ptr, 0x0d), shl(0xe0, assetIndex))
      mstore(add(ptr, 0x11), shl(0xf8, routeType))
      mstore(add(ptr, 0x12), shl(0xc0, baseAmount))
      mstore(0x40, add(buf, 0x3a))
    }
  }

  uint8 internal constant PACKED_COMMON_PERPS_DATA_BYTES = 55;
  uint8 internal constant PACKED_CREATE_MARKET_PERPS_BYTES = 4 + PACKED_COMMON_PERPS_DATA_BYTES;
  uint8 internal constant PACKED_COMMON_SPOT_DATA_BYTES = 26;
  uint8 internal constant PACKED_CREATE_MARKET_SPOT_BYTES = 22 + PACKED_COMMON_SPOT_DATA_BYTES;

  /// @notice Read all CreateMarketSpotData fields from packed calldata onto the stack.
  /// Layout (48 bytes): baseAssetIndex(4) | quoteAssetIndex(4) | sizeExtMul(7) | quoteExtMul(7)
  ///   | takerFee(4) | makerFee(4) | minBaseAmount(6) | minQuoteAmount(6) | orderQuoteLimit(6)
  function readCreateMarketSpotData(
    bytes calldata _data
  )
    internal
    pure
    returns (
      uint32 baseAssetIndex,
      uint32 quoteAssetIndex,
      uint56 sizeExtensionMultiplier,
      uint56 quoteExtensionMultiplier,
      uint32 takerFee,
      uint32 makerFee,
      uint48 minBaseAmount,
      uint48 minQuoteAmount,
      uint48 orderQuoteLimit
    )
  {
    baseAssetIndex = Bytes.unsafeReadU32At(_data, 0x00);
    quoteAssetIndex = Bytes.unsafeReadU32At(_data, 0x04);
    sizeExtensionMultiplier = Bytes.unsafeReadU56At(_data, 0x08);
    quoteExtensionMultiplier = Bytes.unsafeReadU56At(_data, 0x0f);
    takerFee = Bytes.unsafeReadU32At(_data, 0x16);
    makerFee = Bytes.unsafeReadU32At(_data, 0x1a);
    minBaseAmount = Bytes.unsafeReadU48At(_data, 0x1e);
    minQuoteAmount = Bytes.unsafeReadU48At(_data, 0x24);
    orderQuoteLimit = Bytes.unsafeReadU48At(_data, 0x2a);
  }

  struct CreateMarket {
    uint16 marketIndex;
    MarketType marketType;
    bytes marketData;
  }

  /// @notice Serialize create order book pubData, it does not include metadata
  /// Layout: type(1) | marketIndex(2) | marketType(1) | marketData(N) = 4+N bytes
  /// @param marketType Caller must provide an in-bounds MarketType enum value.
  function writeCreateMarketPubDataForPriorityQueue(
    uint16 marketIndex,
    MarketType marketType,
    bytes calldata marketData
  ) internal pure returns (bytes memory buf) {
    assembly {
      let dataLen := marketData.length
      let totalLen := add(0x04, dataLen)
      buf := mload(0x40)
      mstore(buf, totalLen)
      let ptr := add(buf, 0x20)
      mstore8(ptr, PriorityPubDataTypeL1CreateMarket)
      mstore(add(ptr, 0x01), shl(0xf0, marketIndex))
      mstore(add(ptr, 0x03), shl(0xf8, marketType))
      calldatacopy(add(ptr, 0x04), marketData.offset, dataLen)
      mstore(0x40, add(buf, add(totalLen, 0x20)))
    }
  }

  /// @notice Serialize create order book pubData, includes metadata
  /// Layout: _data(N) | size_decimals(1) | price_decimals(1) | symbol(32) = N+34 bytes
  function writeCreateMarketPubDataForPriorityQueueWithMetadata(
    bytes memory _data,
    uint8 size_decimals,
    uint8 price_decimals,
    bytes32 symbol
  ) internal pure returns (bytes memory buf) {
    assembly {
      let dataLen := mload(_data)
      let totalLen := add(dataLen, 0x22)
      buf := mload(0x40)
      mstore(buf, totalLen)
      let dst := add(buf, 0x20)
      mcopy(dst, add(_data, 0x20), dataLen)
      let tail := add(dst, dataLen)
      mstore8(tail, size_decimals)
      mstore(add(tail, 0x01), shl(0xf8, price_decimals))
      mstore(add(tail, 0x02), symbol)
      mstore(0x40, add(buf, add(totalLen, 0x20)))
    }
  }

  struct UpdateMarket {
    uint16 marketIndex;
    MarketType marketType;
    bytes marketData;
  }

  uint8 internal constant PACKED_UPDATE_MARKET_PERPS_BYTES = 1 + PACKED_COMMON_PERPS_DATA_BYTES;
  uint8 internal constant PACKED_UPDATE_MARKET_SPOT_BYTES = 1 + PACKED_COMMON_SPOT_DATA_BYTES;

  /// @notice Read all UpdateMarketSpot fields from packed calldata onto the stack.
  /// Layout (27 bytes): status(1) | takerFee(4) | makerFee(4) | minBaseAmount(6) | minQuoteAmount(6) | orderQuoteLimit(6)
  function readUpdateMarketSpotData(
    bytes calldata _data
  ) internal pure returns (uint8 status, uint32 takerFee, uint32 makerFee, uint48 minBaseAmount, uint48 minQuoteAmount, uint48 orderQuoteLimit) {
    status = Bytes.unsafeReadU8At(_data, 0x00);
    takerFee = Bytes.unsafeReadU32At(_data, 0x01);
    makerFee = Bytes.unsafeReadU32At(_data, 0x05);
    minBaseAmount = Bytes.unsafeReadU48At(_data, 0x09);
    minQuoteAmount = Bytes.unsafeReadU48At(_data, 0x0f);
    orderQuoteLimit = Bytes.unsafeReadU48At(_data, 0x15);
  }

  /// @notice Serialize update order book pubData
  /// Layout: type(1) | marketIndex(2) | marketType(1) | marketData(N) = 4+N bytes
  /// @param marketType Caller must provide an in-bounds MarketType enum value.
  function writeUpdateMarketPubDataForPriorityQueue(
    uint16 marketIndex,
    MarketType marketType,
    bytes calldata marketData
  ) internal pure returns (bytes memory buf) {
    assembly {
      let dataLen := marketData.length
      let totalLen := add(0x04, dataLen)
      buf := mload(0x40)
      mstore(buf, totalLen)
      let ptr := add(buf, 0x20)
      mstore8(ptr, PriorityPubDataTypeL1UpdateMarket)
      mstore(add(ptr, 0x01), shl(0xf0, marketIndex))
      mstore(add(ptr, 0x03), shl(0xf8, marketType))
      calldatacopy(add(ptr, 0x04), marketData.offset, dataLen)
      mstore(0x40, add(buf, add(totalLen, 0x20)))
    }
  }

  /// @notice Serialize create order pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) | marketIndex(2) | baseAmount(6) | price(4) | isAsk(1) | orderType(1) = 27 bytes
  function writeCreateOrderPubDataForPriorityQueue(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint16 marketIndex,
    uint48 baseAmount,
    uint32 price,
    uint8 isAsk,
    uint8 orderType
  ) internal pure returns (bytes memory buf) {
    assembly {
      buf := mload(0x40)
      mstore(buf, 0x1b)
      let ptr := add(buf, 0x20)
      mstore8(ptr, PriorityPubDataTypeL1CreateOrder)
      mstore(add(ptr, 0x01), shl(0xd0, accountIndex))
      mstore(add(ptr, 0x07), shl(0xd0, masterAccountIndex))
      mstore(add(ptr, 0x0d), shl(0xf0, marketIndex))
      mstore(add(ptr, 0x0f), shl(0xd0, baseAmount))
      mstore(add(ptr, 0x15), shl(0xe0, price))
      mstore(add(ptr, 0x19), shl(0xf8, isAsk))
      mstore(add(ptr, 0x1a), shl(0xf8, orderType))
      mstore(0x40, add(buf, 0x3b))
    }
  }

  /// @notice Serialize burn shares pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) | publicPoolIndex(6) | sharesAmount(8) = 27 bytes
  function writeBurnSharesPubDataForPriorityQueue(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint48 publicPoolIndex,
    uint64 sharesAmount
  ) internal pure returns (bytes memory buf) {
    assembly {
      buf := mload(0x40)
      mstore(buf, 0x1b)
      let ptr := add(buf, 0x20)
      mstore8(ptr, PriorityPubDataTypeL1BurnShares)
      mstore(add(ptr, 0x01), shl(0xd0, accountIndex))
      mstore(add(ptr, 0x07), shl(0xd0, masterAccountIndex))
      mstore(add(ptr, 0x0d), shl(0xd0, publicPoolIndex))
      mstore(add(ptr, 0x13), shl(0xc0, sharesAmount))
      mstore(0x40, add(buf, 0x3b))
    }
  }

  /// @notice Serialize cancel all orders pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) = 13 bytes
  function writeCancelAllOrdersPubDataForPriorityQueue(uint48 accountIndex, uint48 masterAccountIndex) internal pure returns (bytes memory buf) {
    assembly {
      buf := mload(0x40)
      mstore(buf, 0x0d)
      let ptr := add(buf, 0x20)
      mstore8(ptr, PriorityPubDataTypeL1CancelAllOrders)
      mstore(add(ptr, 0x01), shl(0xd0, accountIndex))
      mstore(add(ptr, 0x07), shl(0xd0, masterAccountIndex))
      mstore(0x40, add(buf, 0x2d))
    }
  }

  /// @notice Serialize change pub key pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) | apiKeyIndex(1) | pubKey(N) = 14+N bytes
  function writeChangePubKeyPubDataForPriorityQueue(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint8 apiKeyIndex,
    bytes calldata pubKey
  ) internal pure returns (bytes memory buf) {
    assembly {
      let dataLen := pubKey.length
      let totalLen := add(0x0e, dataLen)
      buf := mload(0x40)
      mstore(buf, totalLen)
      let ptr := add(buf, 0x20)
      mstore8(ptr, PriorityPubDataTypeL1ChangePubKey)
      mstore(add(ptr, 0x01), shl(0xd0, accountIndex))
      mstore(add(ptr, 0x07), shl(0xd0, masterAccountIndex))
      mstore(add(ptr, 0x0d), shl(0xf8, apiKeyIndex))
      calldatacopy(add(ptr, 0x0e), pubKey.offset, dataLen)
      mstore(0x40, add(buf, add(totalLen, 0x20)))
    }
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
    uint32 assetIndex; // Asset index of the token being registered
    uint64 minL2TransferAmount; // Minimum L2 transfer amount for the asset
    uint64 minL2WithdrawalAmount; // Minimum L2 withdrawal amount for the asset
    uint8 marginMode; // 0 if disabled, 1 if enabled
    uint16 loanToValue;
    uint16 liquidationThreshold;
    uint16 liquidationFactor;
    uint32 liquidationFee;
    uint56 indexPriceDivider; // Extended asset balance * index price / indexPriceDivider = extended USDC value
  }

  /// @notice Serialize the common register asset priority payload
  function writeRegisterAssetPubDataForPriorityQueue(
    uint8 pubdataType,
    uint56 extensionMultiplier,
    uint8 coreDecimals,
    RegisterAsset calldata params
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(
      pubdataType,
      params.assetIndex,
      extensionMultiplier,
      params.minL2TransferAmount,
      params.minL2WithdrawalAmount,
      params.marginMode,
      params.loanToValue,
      params.liquidationThreshold,
      params.liquidationFactor,
      params.liquidationFee,
      params.indexPriceDivider,
      coreDecimals
    );
  }

  /// @notice Append unhashed register asset metadata
  function writeRegisterAssetPubDataForPriorityQueueWithMetadata(
    bytes memory _data,
    uint8 l1Decimals,
    uint8 priceDecimals,
    uint128 tickSize,
    bytes32 symbol
  ) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(_data, l1Decimals, priceDecimals, tickSize, symbol);
  }

  struct UpdateAsset {
    uint32 assetIndex; // Asset index of the token being updated
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
    uint32 assetIndex,
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

  /// @notice Serialize sendToEvm pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) | assetIndex(4) | evmRecipient(20) | routeType(1) | baseAmount(8) = 46 bytes
  /// @param routeType Caller must provide an in-bounds RouteType enum value.
  function writeSendToEvmPubDataForPriorityQueue(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint32 assetIndex,
    address evmRecipient,
    RouteType routeType,
    uint64 baseAmount
  ) internal pure returns (bytes memory buf) {
    assembly {
      buf := mload(0x40)
      mstore(buf, 0x2e)
      let ptr := add(buf, 0x20)
      mstore8(ptr, PriorityPubDataTypeL1SendToEvm)
      mstore(add(ptr, 0x01), shl(0xd0, accountIndex))
      mstore(add(ptr, 0x07), shl(0xd0, masterAccountIndex))
      mstore(add(ptr, 0x0d), shl(0xe0, assetIndex))
      mstore(add(ptr, 0x11), shl(0x60, evmRecipient))
      mstore(add(ptr, 0x25), shl(0xf8, routeType))
      mstore(add(ptr, 0x26), shl(0xc0, baseAmount))
      mstore(0x40, add(buf, 0x4e))
    }
  }

  /// @notice Serialize withdrawToL1Address pubData
  /// Layout: type(1) | accountIndex(6) | masterAccountIndex(6) | assetIndex(4) | l1Recipient(20) | routeType(1) | baseAmount(8) = 46 bytes
  /// @param routeType Caller must provide an in-bounds RouteType enum value.
  function writeWithdrawToL1AddressPubDataForPriorityQueue(
    uint48 accountIndex,
    uint48 masterAccountIndex,
    uint32 assetIndex,
    address l1Recipient,
    RouteType routeType,
    uint64 baseAmount
  ) internal pure returns (bytes memory buf) {
    assembly {
      buf := mload(0x40)
      mstore(buf, 0x2e)
      let ptr := add(buf, 0x20)
      mstore8(ptr, PriorityPubDataTypeL1WithdrawToL1Address)
      mstore(add(ptr, 0x01), shl(0xd0, accountIndex))
      mstore(add(ptr, 0x07), shl(0xd0, masterAccountIndex))
      mstore(add(ptr, 0x0d), shl(0xe0, assetIndex))
      mstore(add(ptr, 0x11), shl(0x60, l1Recipient))
      mstore(add(ptr, 0x25), shl(0xf8, routeType))
      mstore(add(ptr, 0x26), shl(0xc0, baseAmount))
      mstore(0x40, add(buf, 0x4e))
    }
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                   EVM TO CORE MESSAGES                     */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  uint8 constant EvmWriteTypeChangePubKey = 0x40;
  uint8 constant EvmWriteTypeCreateOrder = 0x41;
  uint8 constant EvmWriteTypeCancelOrder = 0x42;
  uint8 constant EvmWriteTypeCancelAllOrders = 0x43;
  uint8 constant EvmWriteTypeSendToCore = 0x44;
  uint8 constant EvmWriteTypeFinalizeEvmLink = 0x45;
  uint8 constant EvmWriteTypeSendToEvm = 0x46;
  uint8 constant EvmWriteTypeBurnShares = 0x47;
  uint8 constant EvmWriteTypeWithdrawToL1Address = 0x48;

  /// @notice Serialize EVM change pubkey request
  /// Layout: type(1) | accountIndex(6) | apiKeyIndex(1) | pubKey(N)
  function writeEvmChangePubKey(uint48 accountIndex, uint8 apiKeyIndex, bytes calldata pubKey) internal pure returns (bytes memory) {
    return abi.encodePacked(EvmWriteTypeChangePubKey, accountIndex, apiKeyIndex, pubKey);
  }

  /// @notice Serialize EVM create order request
  /// Layout: type(1) | accountIndex(6) | marketIndex(2) | clientOrderIndex(6) | orderType(1) | timeInForce(1) | orderExpiry(8) | amount(6) | price(4) | isAsk(1) | reduceOnly(1) | triggerPrice(4) = 41 bytes
  function writeEvmCreateOrder(
    uint48 accountIndex,
    uint16 marketIndex,
    uint48 clientOrderIndex,
    uint8 orderType,
    uint8 timeInForce,
    uint64 orderExpiry,
    uint48 amount,
    uint32 price,
    bool isAsk,
    bool reduceOnly,
    uint32 triggerPrice
  ) internal pure returns (bytes memory buf) {
    assembly {
      buf := mload(0x40)
      mstore(buf, 0x29) // 41 bytes
      let ptr := add(buf, 0x20)
      mstore8(ptr, EvmWriteTypeCreateOrder)
      mstore(add(ptr, 0x01), shl(0xd0, accountIndex)) // 6 bytes
      mstore(add(ptr, 0x07), shl(0xf0, marketIndex)) // 2 bytes
      mstore(add(ptr, 0x09), shl(0xd0, clientOrderIndex)) // 6 bytes
      mstore(add(ptr, 0x0f), shl(0xf8, orderType)) // 1 byte
      mstore(add(ptr, 0x10), shl(0xf8, timeInForce)) // 1 byte
      mstore(add(ptr, 0x11), shl(0xc0, orderExpiry)) // 8 bytes
      mstore(add(ptr, 0x19), shl(0xd0, amount)) // 6 bytes
      mstore(add(ptr, 0x1f), shl(0xe0, price)) // 4 bytes
      mstore8(add(ptr, 0x23), iszero(iszero(isAsk))) // 1 byte (coerced to 0 or 1)
      mstore8(add(ptr, 0x24), iszero(iszero(reduceOnly))) // 1 byte (coerced to 0 or 1)
      mstore(add(ptr, 0x25), shl(0xe0, triggerPrice)) // 4 bytes
      mstore(0x40, add(buf, 0x49))
    }
  }

  /// @notice Serialize EVM cancel order request
  /// Layout: type(1) | accountIndex(6) | orderIndex(8) = 15 bytes
  function writeEvmCancelOrder(uint48 accountIndex, uint64 orderIndex) internal pure returns (bytes memory buf) {
    assembly {
      buf := mload(0x40)
      mstore(buf, 0x0f) // 15 bytes
      let ptr := add(buf, 0x20)
      mstore8(ptr, EvmWriteTypeCancelOrder)
      mstore(add(ptr, 0x01), shl(0xd0, accountIndex))
      mstore(add(ptr, 0x07), shl(0xc0, orderIndex)) // 8 bytes, shift = 256-64 = 192 = 0xc0
      mstore(0x40, add(buf, 0x2f))
    }
  }

  /// @notice Serialize EVM cancel all orders request
  /// Layout: type(1) | accountIndex(6) = 7 bytes
  function writeEvmCancelAllOrders(uint48 accountIndex) internal pure returns (bytes memory buf) {
    assembly {
      buf := mload(0x40)
      mstore(buf, 0x07) // 7 bytes
      let ptr := add(buf, 0x20)
      mstore8(ptr, EvmWriteTypeCancelAllOrders)
      mstore(add(ptr, 0x01), shl(0xd0, accountIndex))
      mstore(0x40, add(buf, 0x27))
    }
  }

  /// @notice Serialize EVM send to core request
  /// Layout: type(1) | assetIndex(4) | to(20) | isL1Account(1) | routeType(1) | baseAmount(8) = 35 bytes
  /// @param routeType Caller must provide an in-bounds RouteType enum value.
  function writeEvmSendToCore(
    uint32 assetIndex,
    address to,
    bool isL1Account,
    RouteType routeType,
    uint64 baseAmount
  ) internal pure returns (bytes memory buf) {
    assembly {
      buf := mload(0x40)
      mstore(buf, 0x23) // 35 bytes
      let ptr := add(buf, 0x20)
      mstore8(ptr, EvmWriteTypeSendToCore)
      mstore(add(ptr, 0x01), shl(0xe0, assetIndex))
      mstore(add(ptr, 0x05), shl(0x60, to))
      mstore8(add(ptr, 0x19), iszero(iszero(isL1Account)))
      mstore8(add(ptr, 0x1a), routeType)
      mstore(add(ptr, 0x1b), shl(0xc0, baseAmount))
      mstore(0x40, add(buf, 0x43))
    }
  }

  /// @notice Serialize EVM finalize EVM link request (0x45)
  /// Layout: type(1) | assetIndex(4) | evmToken(20) = 25 bytes
  function writeEvmFinalizeEvmLink(uint32 assetIndex, address evmToken) internal pure returns (bytes memory) {
    return abi.encodePacked(EvmWriteTypeFinalizeEvmLink, assetIndex, evmToken);
  }

  /// @notice Serialize EVM send to EVM request (0x46)
  /// Layout: type(1) | accountIndex(6) | assetIndex(4) | evmRecipient(20) | routeType(1) | baseAmount(8) = 40 bytes
  /// @param routeType Caller must provide an in-bounds RouteType enum value.
  function writeEvmSendToEvm(
    uint48 accountIndex,
    uint32 assetIndex,
    address evmRecipient,
    RouteType routeType,
    uint64 baseAmount
  ) internal pure returns (bytes memory buf) {
    assembly {
      buf := mload(0x40)
      mstore(buf, 0x28) // 40 bytes
      let ptr := add(buf, 0x20)
      mstore8(ptr, EvmWriteTypeSendToEvm)
      mstore(add(ptr, 0x01), shl(0xd0, accountIndex))
      mstore(add(ptr, 0x07), shl(0xe0, assetIndex))
      mstore(add(ptr, 0x0b), shl(0x60, evmRecipient))
      mstore8(add(ptr, 0x1f), routeType)
      mstore(add(ptr, 0x20), shl(0xc0, baseAmount))
      mstore(0x40, add(buf, 0x48))
    }
  }

  /// @notice Serialize EVM burn shares request (0x47)
  /// Layout: type(1) | accountIndex(6) | publicPoolIndex(6) | shareAmount(8) = 21 bytes
  function writeEvmBurnShares(uint48 accountIndex, uint48 publicPoolIndex, uint64 shareAmount) internal pure returns (bytes memory) {
    return abi.encodePacked(EvmWriteTypeBurnShares, accountIndex, publicPoolIndex, shareAmount);
  }

  /// @notice Serialize EVM withdraw to L1 address request (0x48).
  /// Layout: type(1) | accountIndex(6) | assetIndex(4) | l1Recipient(20) | routeType(1) | baseAmount(8) = 40 bytes
  function writeEvmWithdrawToL1Address(
    uint48 accountIndex,
    uint32 assetIndex,
    address l1Recipient,
    RouteType routeType,
    uint64 baseAmount
  ) internal pure returns (bytes memory) {
    return abi.encodePacked(EvmWriteTypeWithdrawToL1Address, accountIndex, assetIndex, l1Recipient, routeType, baseAmount);
  }
}
