// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import {IMintGateway} from "./IMintGateway.sol";

/// @title IL1MintGateway
/// @notice Full interface for the L1-side mint gateway for EVM-native tokens.
interface IL1MintGateway is IMintGateway {
  /// @notice Burn wrapped tokens and send a cross-chain message to release on EVM.
  /// @param token The wrapped token to burn.
  /// @param to The recipient address on EVM.
  /// @param amount The amount to burn and bridge.
  /// @param gasLimit The gas limit for the cross-chain message.
  function sendTokens(address token, address to, uint256 amount, uint256 gasLimit) external payable;

  /// @notice Burn wrapped tokens and send a cross-chain message to release on EVM,
  /// with a custom refund address for failed messages.
  /// @param token The wrapped token to burn.
  /// @param to The recipient address on EVM.
  /// @param amount The amount to burn and bridge.
  /// @param refundAddress The address to receive refunds on failed messages.
  /// @param gasLimit The gas limit for the cross-chain message.
  function sendTokensCustomRefund(address token, address to, uint256 amount, address refundAddress, uint256 gasLimit) external payable;
}
