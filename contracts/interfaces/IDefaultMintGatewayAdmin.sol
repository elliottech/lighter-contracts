// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

/// @title IDefaultMintGatewayAdmin
/// @notice Admin surface for default mint gateways.
interface IDefaultMintGatewayAdmin {
  /// @notice Updates the beacon implementation used by gateway-deployed wrapped tokens.
  /// @param newImpl The new wrapped-token implementation.
  function setTokenImplementation(address newImpl) external;
}
