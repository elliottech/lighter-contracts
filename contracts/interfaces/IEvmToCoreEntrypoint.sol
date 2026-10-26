// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import {TxTypes} from "../lib/TxTypes.sol";

interface IEvmToCoreEntrypoint {
  // EvmInteropManager-only
  function registerSendToEvm(
    address sender,
    uint48 accountIndex,
    uint32 assetIndex,
    address evmRecipient,
    TxTypes.RouteType routeType,
    uint64 baseAmount
  ) external returns (uint64 reqId);
  function registerSendToCore(
    address sender,
    uint32 assetIndex,
    address to,
    bool isL1Account,
    TxTypes.RouteType routeType,
    uint64 baseAmount
  ) external returns (uint64 reqId);
  function finalizeEvmLink(uint32 assetIndex, address evmToken) external returns (uint64 reqId);

  // User-facing
  function changePubKey(uint48 accountIndex, uint8 apiKeyIndex, bytes calldata pubKey) external returns (uint64 reqId);
  function createOrder(
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
  ) external returns (uint64 reqId);
  function cancelOrder(uint48 accountIndex, uint64 orderIndex) external returns (uint64 reqId);
  function cancelAllOrders(uint48 accountIndex) external returns (uint64 reqId);
  function burnShares(uint48 accountIndex, uint48 publicPoolIndex, uint64 shareAmount) external returns (uint64 reqId);
  function withdrawToL1Address(
    uint48 accountIndex,
    uint32 assetIndex,
    address l1Recipient,
    TxTypes.RouteType routeType,
    uint64 baseAmount
  ) external returns (uint64 reqId);
}
