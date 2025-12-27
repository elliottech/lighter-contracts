// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "./Bytes.sol";

/// @title zkLighter TxTypes Library
/// @notice Implements helper functions to serialize and deserialize tx types
/// @author zkLighter Team
library TxTypes {
  /// @notice zklighter priority request types
  uint8 constant PriorityPubDataTypeEmpty = 30;
  uint8 constant PriorityPubDataTypeL1Deposit = 31;
  uint8 constant PriorityPubDataTypeL1ChangePubKey = 32;
  uint8 constant PriorityPubDataTypeL1CreateMarket = 33;
  uint8 constant PriorityPubDataTypeL1UpdateMarket = 34;
  uint8 constant PriorityPubDataTypeL1CancelAllOrders = 35;
  uint8 constant PriorityPubDataTypeL1Withdraw = 36;
  uint8 constant PriorityPubDataTypeL1CreateOrder = 37;
  uint8 constant PriorityPubDataTypeL1BurnShares = 38;

  /// @notice zklighter onchain transaction types
  enum OnChainPubDataType {
    Empty,
    Withdraw
  }

  /// @notice Size of the withdraw log in bytes
  uint32 internal constant WithdrawLogSize = 15; // 1 byte for type, 6 bytes for accountIndex, 8 bytes for usdcAmount

  enum OrderType {
    LimitOrder,
    MarketOrder
  }

  uint8 internal constant TX_TYPE_BYTES = 1;
  uint8 internal constant DESERT_EXIT_SIZE = 22;
  uint256 internal constant PACKED_TX_MAX_PUBDATA_BYTES = 73;
  uint256 internal constant DEPOSIT_PUB_DATA_SIZE = 35;

  struct Deposit {
    uint48 accountIndex;
    address toAddress;
    uint64 amount;
  }

  /// @notice Serialize deposit pubData
  function writeDepositPubDataForPriorityQueue(Deposit memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1Deposit), _tx.accountIndex, _tx.toAddress, _tx.amount);
  }

  /// @notice Deserialize deposit pubData
  function readDepositForDesertMode(bytes memory _data) internal pure returns (uint48 accountIndex, uint64 amount) {
    uint256 _offset = 1; // Skipping the tx type
    (_offset, accountIndex) = Bytes.readUInt48(_data, _offset);
    _offset += 20; // Skipping the address
    (_offset, amount) = Bytes.readUInt64(_data, _offset);
    return (accountIndex, amount);
  }

  struct L1Withdraw {
    uint48 accountIndex;
    uint48 masterAccountIndex;
    uint64 usdcAmount;
  }

  /// @notice Serialize withdraw pubData
  function writeWithdrawPubDataForPriorityQueue(L1Withdraw memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(uint8(PriorityPubDataTypeL1Withdraw), _tx.accountIndex, _tx.masterAccountIndex, _tx.usdcAmount);
  }

  struct Withdraw {
    uint48 masterAccountIndex;
    uint64 usdcAmount;
  }

  /// @notice Deserialize withdraw pubData
  function readWithdrawOnChainLog(bytes memory _data, uint256 _offset) internal pure returns (Withdraw memory parsed, uint256 newOffset) {
    _offset++; // Skipping the type
    (_offset, parsed.masterAccountIndex) = Bytes.readUInt48(_data, _offset);
    (_offset, parsed.usdcAmount) = Bytes.readUInt64(_data, _offset);
    return (parsed, _offset);
  }

  struct CreateMarket {
    uint8 marketIndex;
    uint32 quoteMultiplier;
    uint32 takerFee;
    uint32 makerFee;
    uint32 liquidationFee;
    uint64 minBaseAmount;
    uint64 minQuoteAmount;
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

  struct CreateOrder {
    uint48 accountIndex;
    uint48 masterAccountIndex;
    uint8 marketIndex;
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

  /// @notice Serialize create order book pubData, it does not include metadata
  function writeCreateMarketPubDataForPriorityQueue(CreateMarket memory _tx) internal pure returns (bytes memory buf) {
    bytes memory suffix = writeCreateMarketPubDataForPriorityQueueSuffix(_tx);
    buf = abi.encodePacked(
      uint8(PriorityPubDataTypeL1CreateMarket),
      _tx.marketIndex,
      _tx.quoteMultiplier,
      _tx.takerFee,
      _tx.makerFee,
      _tx.liquidationFee,
      _tx.minBaseAmount,
      _tx.minQuoteAmount,
      _tx.defaultInitialMarginFraction,
      _tx.minInitialMarginFraction,
      _tx.maintenanceMarginFraction,
      _tx.closeOutMarginFraction,
      _tx.interestRate,
      suffix
    );
  }

  function writeCreateMarketPubDataForPriorityQueueSuffix(CreateMarket memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(_tx.fundingClampSmall, _tx.fundingClampBig, _tx.openInterestLimit, _tx.orderQuoteLimit);
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
    uint8 marketIndex;
    uint8 status;
    uint32 takerFee;
    uint32 makerFee;
    uint32 liquidationFee;
    uint64 minBaseAmount;
    uint64 minQuoteAmount;
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

  /// @notice Serialize update order book pubData
  function writeUpdateMarketPubDataForPriorityQueue(UpdateMarket memory _tx) internal pure returns (bytes memory buf) {
    bytes memory suffix = writeUpdateMarketPubDataSuffixForPriorityQueue(_tx);
    buf = abi.encodePacked(
      uint8(PriorityPubDataTypeL1UpdateMarket),
      _tx.marketIndex,
      _tx.status,
      _tx.takerFee,
      _tx.makerFee,
      _tx.liquidationFee,
      _tx.minBaseAmount,
      _tx.minQuoteAmount,
      _tx.defaultInitialMarginFraction,
      _tx.minInitialMarginFraction,
      _tx.maintenanceMarginFraction,
      _tx.closeOutMarginFraction,
      _tx.interestRate,
      suffix
    );
  }

  function writeUpdateMarketPubDataSuffixForPriorityQueue(UpdateMarket memory _tx) internal pure returns (bytes memory buf) {
    buf = abi.encodePacked(_tx.fundingClampSmall, _tx.fundingClampBig, _tx.openInterestLimit, _tx.orderQuoteLimit);
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
}
