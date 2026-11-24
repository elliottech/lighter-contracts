// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "../interfaces/IDesertVerifier.sol";

contract DesertVerifierTest is IDesertVerifier {
  bool private checkExpectedPublicInput;
  uint256 private expectedPublicInput;

  function Verify(bytes calldata proof, uint256[] calldata public_inputs) external view returns (bool success) {
    return !checkExpectedPublicInput || (public_inputs.length == 1 && public_inputs[0] == expectedPublicInput);
  }

  function setExpectedPublicInput(uint256 _expectedPublicInput) external {
    expectedPublicInput = _expectedPublicInput;
    checkExpectedPublicInput = true;
  }

  // avoid same bytecode as DesertVerifier
  function nouse() external {}
}
