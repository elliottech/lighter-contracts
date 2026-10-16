// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

/// @title IEscrowGateway
/// @notice Interface for escrow gateways that lock canonical tokens when bridging.
interface IEscrowGateway {
  /// @notice The counterpart mint gateway on the remote chain.
  function externalGateway() external view returns (address);

  /// @notice Unlock escrowed tokens to the recipient.
  /// @param localToken The escrowed canonical token to release.
  /// @param to The recipient address.
  /// @param amount The amount to unlock.
  function unlock(address localToken, address to, uint256 amount) external;
}
