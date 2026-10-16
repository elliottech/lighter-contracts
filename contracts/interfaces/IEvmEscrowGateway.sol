// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import {IEscrowGateway} from "./IEscrowGateway.sol";

/// @title IEvmEscrowGateway
/// @notice Full interface for the EVM-side escrow gateway for EVM-native tokens.
interface IEvmEscrowGateway is IEscrowGateway {
  /// @notice Lock tokens in escrow and send a cross-chain message to mint on L1.
  /// @param token The canonical token to lock.
  /// @param to The recipient address on L1.
  /// @param amount The amount to lock and bridge.
  function sendTokens(address token, address to, uint256 amount) external;
}
