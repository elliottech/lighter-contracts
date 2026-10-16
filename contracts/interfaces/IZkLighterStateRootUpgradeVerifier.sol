// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

/// @title zkLighter State Root Upgrade Verifier Interface
/// @author zkLighter Team
interface IZkLighterStateRootUpgradeVerifier {
  function Verify(bytes calldata proof, uint256[] calldata public_inputs) external view returns (bool success);
}
