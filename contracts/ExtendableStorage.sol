// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./interfaces/IZkLighterStateRootUpgradeVerifier.sol";

/// @title zkLighter Extendable Storage Contract
/// @author zkLighter Team
contract ExtendableStorage {
  uint256[420] private __gap;

  /// @dev Stores new state root at the batch number if state root upgrade happened
  mapping(uint64 => bytes32) public stateRootUpdates;

  /// @dev Verifier contract, used for verifying state root upgrade proofs
  IZkLighterStateRootUpgradeVerifier internal stateRootUpgradeVerifier;

  /// @dev Stores if the desert mode was performed for the account index
  mapping(uint48 => bool) internal accountPerformedDesert;
}
