// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity 0.8.25;

/// @title Interface of the upgradeable contract
/// @author Matter Labs (https://github.com/matter-labs/zksync/blob/master/contracts/contracts/Upgradeable.sol)
interface IUpgradeable {
  /// @notice Upgrades target of upgradeable contract
  /// @param newTarget New target
  /// @param newTargetInitializationParameters New target initialization parameters
  function upgradeTarget(address newTarget, bytes calldata newTargetInitializationParameters) external;
}
