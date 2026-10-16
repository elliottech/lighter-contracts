// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import {TxTypes} from "../lib/TxTypes.sol";
import {IL1InteropManager} from "./IL1InteropManager.sol";

interface IL1CoreMessaging {
  function INTEROP_MANAGER() external view returns (IL1InteropManager);
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
  ) external;
  function registerEvmNativeAssetOnCore(
    address sender,
    uint8 evmDecimals,
    uint8 coreDecimals,
    uint8 priceDecimals,
    uint56 extensionMultiplier,
    uint128 tickSize,
    bytes32 symbol,
    TxTypes.RegisterAsset calldata _params
  ) external;
  function registerCoreNativeAssetOnCore(
    address sender,
    uint8 coreDecimals,
    uint8 priceDecimals,
    uint56 extensionMultiplier,
    uint128 tickSize,
    bytes32 symbol,
    TxTypes.RegisterAsset calldata _params
  ) external;
  function registerDeposit(address sender, address to, uint32 assetIndex, TxTypes.RouteType routeType, uint64 baseAmount) external payable;
  function finalizeEvmWrapperLink(address sender, uint32 assetIndex, address evmWrapper) external;
  function finalizeL1WrapperLink(address sender, uint32 assetIndex, address l1Wrapper) external;
  function getAccountIndexFromAddress(address _address) external view returns (uint48);
  function getSystemAddress(uint48 _accountIndex) external view returns (address);
}
