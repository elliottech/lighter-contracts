// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "./interfaces/IZkLighterDesertMode.sol";

/// @title Upgradeable Master Contract
/// @author zkLighter Team
/// @dev UpgradeableMaster is used by the UpgradeGatekeeper when upgrading contracts.
/// It is controlled by the security council. The whole state of the contract is read only.
/// It's indented to be inherited by the UpgradeGatekeeper. Due to this, all methods which are used in the flow of
/// deploying updates are internal.
/// It has 2 main roles:
/// - It delays the deployment of upgrades by at most 3 weeks, in case the upgrade is malicious.
/// This gives users enough time to withdraw the funds using full exit operation from the system.
/// - It stops any upgrade if the system has entered desert mode.
contract UpgradeableMaster {
  /// @notice Notice period changed
  event NoticePeriodChange(uint256 newNoticePeriod);

  /// @dev Notice period before activation of the upgrade (in seconds)
  /// @dev NOTE: Gives users enough time to send full exit requests if the upgrade is malicious
  uint256 internal constant UPGRADE_NOTICE_PERIOD = 3 weeks;

  /// @dev Upgrade notice period, possibly shorten by the security council
  uint256 public approvedUpgradeNoticePeriod;

  /// @dev Upgrade start timestamp
  /// @dev Will be equal to zero if there is no active upgrade
  uint256 public upgradeStartTimestamp;

  /// @dev Instead of keeping a list of council members and requiring approval from all of them,
  /// keep just one council member to simplify the workflow. The council member itself could be a multi signature wallet
  address public immutable securityCouncilAddress;

  /// @dev zkLighter contract used to detect if system is in desert mode. If desert mode is detected, upgrades are not allowed
  IZkLighterDesertMode public immutable zkLighterProxy;

  constructor(address _securityCouncilAddress, address _zkLighterProxy) {
    require(_zkLighterProxy != address(0), "c1");
    securityCouncilAddress = _securityCouncilAddress;
    zkLighterProxy = IZkLighterDesertMode(_zkLighterProxy);
    approvedUpgradeNoticePeriod = UPGRADE_NOTICE_PERIOD;
    emit NoticePeriodChange(approvedUpgradeNoticePeriod);
  }

  /// @notice Minimum notice period before setting the activation preparation for the upgrade
  function getNoticePeriod() internal pure returns (uint256) {
    return 0;
  }

  /// @notice Sets the upgradeStartTimestamp when an upgrade starts
  function upgradeNoticePeriodStarted() internal {
    upgradeStartTimestamp = block.timestamp;
  }

  /// @notice Checks if the upgrade preparation has started for the current upgrade
  function upgradePreparationStarted() internal view {
    require(block.timestamp >= upgradeStartTimestamp + approvedUpgradeNoticePeriod);
  }

  /// @dev Clears the current upgrade when upgrade is finished or canceled
  function clearUpgradeStatus() internal {
    approvedUpgradeNoticePeriod = UPGRADE_NOTICE_PERIOD;
    emit NoticePeriodChange(approvedUpgradeNoticePeriod);
    upgradeStartTimestamp = 0;
  }

  /// @notice Clears the upgrade status when the upgrade is canceled
  function upgradeCanceled() internal {
    clearUpgradeStatus();
  }

  /// @notice Clears the upgrade status when the upgrade is finished
  function upgradeFinishes() internal {
    clearUpgradeStatus();
  }

  /// @notice Checks if the contract can be upgraded (does not allow upgrades in desert mode)
  /// @return bool flag indicating that contract is ready for upgrade
  function isReadyForUpgrade() internal view returns (bool) {
    return !zkLighterProxy.desertMode();
  }

  /// @notice Allows security council to decrease upgrade notice period time to 0
  /// @dev Can only be called after the start of the upgrade (getNoticePeriod)
  function cutUpgradeNoticePeriod(uint256 _upgradeStartTimestamp) external {
    require(upgradeStartTimestamp != 0, "p1");
    require(upgradeStartTimestamp == _upgradeStartTimestamp, "p2"); // given target is not the active upgrade
    require(msg.sender == securityCouncilAddress, "p3"); // only security council can call this

    // decrease upgrade notice period time to zero
    if (approvedUpgradeNoticePeriod > 0) {
      approvedUpgradeNoticePeriod = 0;
      emit NoticePeriodChange(approvedUpgradeNoticePeriod);
    }
  }
}
