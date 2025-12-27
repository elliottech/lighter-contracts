// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity 0.8.25;

import "../UpgradeableMaster.sol";

// UpgradeableMasterTest exposes all methods which are internal as public
contract UpgradeableMasterTest is UpgradeableMaster {
  constructor(address _securityCouncilAddress, address _zkLighterProxy) UpgradeableMaster(_securityCouncilAddress, _zkLighterProxy) {}

  function getNoticePeriodP() public pure returns (uint256) {
    return getNoticePeriod();
  }

  function upgradeNoticePeriodStartedP() public {
    return upgradeNoticePeriodStarted();
  }

  function upgradePreparationStartedP() public {
    upgradePreparationStarted();
  }

  function upgradeCanceledP() public {
    upgradeCanceled();
  }

  function upgradeFinishesP() public {
    upgradeFinishes();
  }

  function isReadyForUpgradeP() public view returns (bool) {
    return isReadyForUpgrade();
  }
}
