// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "../interfaces/IDesertVerifier.sol";

contract DesertVerifierTest is IDesertVerifier {
  function Verify(bytes calldata proof, uint256[] calldata public_inputs) external view returns (bool success) {
    return true;
  }

  // avoid same bytecode as DesertVerifier
  function nouse() external {}
}
