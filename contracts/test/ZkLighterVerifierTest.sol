// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "../interfaces/IZkLighterVerifier.sol";

/// NOTE: NO AUDIT - PLACEHOLDER
/// @title zkLighter Dummy Batch Verifier Contract
/// @author zkLighter Team
contract ZkLighterVerifierTest is IZkLighterVerifier {
  // ------ UPGRADAABLE START ------
  function initialize(bytes calldata) external {}

  /// @notice Verifier contract upgrade. Can be external because Proxy contract intercepts illegal calls of this function.
  /// @param upgradeParameters Encoded representation of upgrade parameters
  function upgrade(bytes calldata upgradeParameters) external {}

  // ------ UPGRADAABLE END ------

  function Verify(bytes calldata proof, uint256[] calldata public_inputs) external view returns (bool success) {
    if (proof.length == 3) {
      // magic number
      return false;
    }

    return true;
  }
}
