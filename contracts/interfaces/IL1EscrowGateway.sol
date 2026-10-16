// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import {IEscrowGateway} from "./IEscrowGateway.sol";

/// @title IL1EscrowGateway
/// @notice Full interface for the L1-side escrow gateway for L1-native tokens.
interface IL1EscrowGateway is IEscrowGateway {
  /// @notice Lock tokens in escrow and send a cross-chain message to mint on EVM with a custom gas limit.
  /// @param token The canonical token to lock.
  /// @param to The recipient address on EVM.
  /// @param amount The amount to lock and bridge.
  /// @param gasLimit The gas limit for the cross-chain message on EVM.
  function sendTokens(address token, address to, uint256 amount, uint256 gasLimit) external payable;

  /// @notice Lock tokens in escrow and send a cross-chain message with a custom gas limit and refund address.
  /// @param token The canonical token to lock.
  /// @param to The recipient address on EVM.
  /// @param amount The amount to lock and bridge.
  /// @param refundAddress The address to receive excess gas refunds on EVM.
  /// @param gasLimit The gas limit for the cross-chain message on EVM.
  function sendTokensCustomRefund(address token, address to, uint256 amount, address refundAddress, uint256 gasLimit) external payable;
}
