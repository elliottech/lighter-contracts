// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import {TxTypes} from "../lib/TxTypes.sol";

interface IEvmInteropManager {
  // Token info registration (admin + metadata)
  function sendTokenInfo(address evmToken) external;

  // Cross-chain receivers from L1 (onlyL1InteropManager)
  function onLinkEvmNativeToken(uint32 assetIndex, address evmToken, bytes calldata metadata) external;
  function onL1NativeGatewaySelection(
    uint32 assetIndex,
    address evmGateway,
    address l1Gateway,
    address expectedEvmWrapper,
    bytes calldata metadata
  ) external;
  function onEvmNativeGatewaySelection(uint32 assetIndex, address evmEscrowGateway, address l1MintGateway, address expectedL1Wrapper) external;
  function setDefaultMintGatewayTokenImplementation(address newImpl) external;

  // Transfers between Core and EVM
  function receiveFromCore(uint32 assetIndex, address to, uint128 baseAmount) external;
  function receiveL1AccountRefund(address l1Address, uint32 assetIndex, uint128 baseAmount) external;
  function sendToEvm(
    uint48 accountIndex,
    uint32 assetIndex,
    address evmRecipient,
    TxTypes.RouteType routeType,
    uint64 baseAmount
  ) external returns (uint64 reqId);
  function sendToCore(
    uint32 assetIndex,
    address to,
    bool isL1Account,
    uint256 amount,
    TxTypes.RouteType routeType
  ) external payable returns (uint64 reqId);
  function sendToCoreWithPermit(
    uint32 assetIndex,
    address to,
    bool isL1Account,
    uint256 amount,
    TxTypes.RouteType routeType,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external returns (uint64 reqId);
}
