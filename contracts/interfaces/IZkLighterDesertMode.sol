// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

/// @title zkLighter DesertMode Interface
/// @author zkLighter Team
interface IZkLighterDesertMode {
  /// @notice Thrown when DesertMode is active
  error ZkLighter_DesertModeActive();

  /// @return True if desert mode is active, false otherwise
  function desertMode() external view returns (bool);
}
