// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity 0.8.25;

/// @title Upgrade events
/// @author Matter Labs (https://github.com/matter-labs/zksync/blob/master/contracts/contracts/Events.sol)
interface IUpgradeEvents {
  /// @notice Event emitted when new upgradeable contract is added to upgrade gatekeeper's list of managed contracts
  event NewUpgradable(uint256 indexed versionId, address indexed upgradeable);

  /// @notice Upgrade mode enter event
  event NoticePeriodStart(
    uint256 indexed versionId,
    address[] newTargets,
    uint256 noticePeriod // In seconds
  );

  /// @notice Upgrade mode cancel event
  event UpgradeCancel(uint256 indexed versionId);

  /// @notice Upgrade mode preparation status event
  event PreparationStart(uint256 indexed versionId);

  /// @notice Upgrade mode complete event
  event UpgradeComplete(uint256 indexed versionId, address[] newTargets);
}
