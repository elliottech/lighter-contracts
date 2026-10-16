// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import {IMintGateway} from "./IMintGateway.sol";

/// @title IEvmMintGateway
/// @notice Full interface for the EVM-side mint gateway for L1-native tokens.
interface IEvmMintGateway is IMintGateway {
  /// @notice Burn wrapped tokens and send a cross-chain message to release on L1.
  /// @param token The wrapped token to burn.
  /// @param to The recipient address on L1.
  /// @param amount The amount to burn and bridge.
  function sendTokens(address token, address to, uint256 amount) external;
}
