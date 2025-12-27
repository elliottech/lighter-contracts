// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "./interfaces/IZkLighterStateRootUpgradeVerifier.sol";

contract ZkLighterStateRootUpgradeVerifier is IZkLighterStateRootUpgradeVerifier {
  function Verify(bytes calldata proof, uint256[] calldata public_inputs) external pure returns (bool success) {
    return true;
  }
}
