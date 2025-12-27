// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../Governance.sol";

contract GovernanceTest is Governance {
  // avoid same bytecode as Governance
  function nouse() external {}

  function overrideValidator(address _validator, bool _active) external {
    validators[_validator] = _active;
  }

  function overrideNetworkGovernor(address _newGovernor) external {
    networkGovernor = _newGovernor;
  }
}
