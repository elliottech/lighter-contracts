// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../Governance.sol";

contract GovernanceTest is Governance {
  error GuardiansAlreadyInitialized();

  // avoid same bytecode as Governance
  function nouse() external {}

  function overrideValidator(address _validator, bool _active) external {
    validators[_validator] = _active;
  }

  function overrideNetworkGovernor(address _newGovernor) external {
    networkGovernor = _newGovernor;
  }

  function overrideUSDCAddress(IERC20 _usdcAddress) external {
    usdc = _usdcAddress;
  }

  function overrideGuardians(address _pauseGuardian, address _emergencyGuardian) external {
    EmergencyPauseStorage storage $ = _emergencyPauseStorage();
    if ($.pauseGuardian != address(0) || $.emergencyGuardian != address(0)) revert GuardiansAlreadyInitialized();
    address oldPauseGuardian = $.pauseGuardian;
    $.pauseGuardian = _pauseGuardian;
    emit PauseGuardianChanged(oldPauseGuardian, _pauseGuardian);

    address oldEmergencyGuardian = $.emergencyGuardian;
    $.emergencyGuardian = _emergencyGuardian;
    emit EmergencyGuardianChanged(oldEmergencyGuardian, _emergencyGuardian);
  }
}
