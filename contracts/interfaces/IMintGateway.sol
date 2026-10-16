// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

/// @title IMintGateway
/// @notice Interface for mint gateways that manage wrapped token representations.
interface IMintGateway {
  /// @notice The counterpart escrow gateway on the remote chain.
  function externalGateway() external view returns (address);

  /// @notice Deploy or verify a wrapped token for the given parameters.
  /// @param salt CREATE2 salt for the wrapped token. For L1/EVM-native tokens,
  /// this is `bytes32(uint256(uint160(externalToken)))`.
  /// @param name The ERC-20 name of the wrapped token.
  /// @param symbol The ERC-20 symbol of the wrapped token.
  /// @param decimals The ERC-20 decimals of the wrapped token.
  function checkOrDeployToken(bytes32 salt, string calldata name, string calldata symbol, uint8 decimals) external;

  /// @notice Mint wrapped tokens to the recipient.
  /// @param localToken The local wrapped token address.
  /// @param to The recipient address.
  /// @param amount The amount to mint.
  /// @param data The use of this param is implementation-specific.
  function mint(address localToken, address to, uint256 amount, bytes calldata data) external;

  /// @notice Burn gateway-deployed wrapped tokens on behalf of InteropManager.
  /// @param localToken The wrapped token to burn.
  /// @param amount The amount to burn.
  function managerBurn(address localToken, uint256 amount) external;
}
