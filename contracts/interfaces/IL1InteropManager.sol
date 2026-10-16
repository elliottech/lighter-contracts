// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "../lib/TxTypes.sol";

import {CanonicalDomain} from "../interop/TokenInteropLib.sol";

struct CoreAssetL1Config {
  CanonicalDomain canonicalDomain;
  address l1Token;
  address coreTokenAdmin;
  uint56 extensionMultiplier;
  uint128 tickSize;
  address l1Gateway;
}

interface IL1InteropManager {
  function sendToCore(uint32 _assetIndex, address to, uint256 amount, TxTypes.RouteType routeType) external payable;
  function linkEvmNativeToken(uint32 assetIndex, address evmToken, uint256 gasLimit) external payable;

  function selectL1NativeGatewayPair(
    uint32 assetIndex,
    address evmGateway,
    address l1Gateway,
    address expectedEvmWrapperToken,
    uint256 gasLimit
  ) external payable;
  function selectEvmNativeGatewayPair(
    uint32 assetIndex,
    address evmGateway,
    address l1Gateway,
    address expectedL1WrapperToken,
    uint256 gasLimit
  ) external payable;
  function setL1ApprovedTokenAdmin(address token, address admin) external;
  function setDefaultL1MintGatewayTokenImplementation(address newImpl) external;
  function setDefaultEvmMintGatewayTokenImplementation(address newImpl, uint256 gasLimit) external payable;

  function finalizeEvmNativeTokenLink(uint32 assetIndex, address evmToken) external;

  function setEvmApprovedTokenInfo(address evmToken, bytes32 slotValue, bytes calldata tokenMetadata) external;
  function finalizeL1NativeGatewayPair(uint32 assetIndex, address l1Gateway, address wrappedEvmToken) external;
  function finalizeEvmNativeGatewayPairOnL1(uint32 assetIndex, address l1Gateway, address l1Wrapper) external;

  function receiveFromCore(uint32 assetIndex, address to, uint128 baseAmount) external;
  function isRegisteredOnL1(uint32 assetIndex) external view returns (bool);
  function getAssetConfig(uint32 assetIndex) external view returns (CoreAssetL1Config memory);
}
