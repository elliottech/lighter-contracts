// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import {Test, Vm} from "forge-std/Test.sol";

import {AdditionalZkLighter} from "../contracts/AdditionalZkLighter.sol";
import {EmergencyPause} from "../contracts/EmergencyPause.sol";
import {Governance} from "../contracts/Governance.sol";
import {IGovernance} from "../contracts/interfaces/IGovernance.sol";
import {IZkLighter} from "../contracts/interfaces/IZkLighter.sol";
import {ZkLighterTest} from "../contracts/test/ZkLighterTest.sol";
import {OwnableERC20} from "../contracts/test/OwnableERC20.sol";
import {ZkLighterVerifierTest} from "../contracts/test/ZkLighterVerifierTest.sol";
import {Proxy} from "../contracts/proxy/Proxy.sol";
import {UpgradeGatekeeper} from "../contracts/proxy/UpgradeGatekeeper.sol";

/// Tests that upgrading Governance resets both pause states and nothing else
contract GovernanceUpgradeClearsPauseTests is Test {
  address internal constant VICTIM_ADDRESS = 0x66Cf2f85115CC20bF439720927C1f93De9672068;
  uint48 internal constant VICTIM_ACCOUNT = 769566;
  address internal constant HACKER_ADDRESS = 0xb3fffca23d4444eE73349825ACD84f7b5020e387;
  uint48 internal constant HACKER_ACCOUNT = 769455;
  uint16 internal constant USDC = 3;
  uint64 internal constant INCIDENT_AMOUNT = 5_096_588_024_995;

  address internal governor = address(0x60F);
  address internal validator = address(0x7A1);
  address internal pauseGuardian = address(0x9A1);
  address internal emergencyGuardian = address(0x9A2);
  address internal securityCouncil = address(0x5EC);

  OwnableERC20 internal usdc;
  Proxy internal governanceProxy;
  Governance internal governance;
  Proxy internal zklighterProxy;
  ZkLighterTest internal zklighter;
  UpgradeGatekeeper internal gatekeeper;

  function setUp() public {
    vm.warp(1_800_000_000);
    usdc = new OwnableERC20("USDC", "USDC", 6);

    governanceProxy = new Proxy(address(new Governance()), abi.encode(governor, address(usdc)));
    governance = Governance(address(governanceProxy));
    vm.startPrank(governor);
    governance.setValidator(validator, true);
    governance.setPauseGuardian(pauseGuardian);
    governance.setEmergencyGuardian(emergencyGuardian);
    vm.stopPrank();

    zklighterProxy = new Proxy(address(new ZkLighterTest()), "");
    zklighter = ZkLighterTest(payable(address(zklighterProxy)));
    zklighter.setGovernanceAddress(address(governance));
    zklighter.setVerifierAddress(address(new ZkLighterVerifierTest()));
    zklighter.setAdditionalZkLighterAddress(address(new AdditionalZkLighter()));
    zklighter.registerDefaultAssetConfigs();
    zklighter.setAddressToAccountIndex(VICTIM_ADDRESS, VICTIM_ACCOUNT);
    zklighter.setAddressToAccountIndex(HACKER_ADDRESS, HACKER_ACCOUNT);
    zklighter.setPendingBalance(USDC, VICTIM_ACCOUNT, INCIDENT_AMOUNT);
    zklighter.setPendingBalance(USDC, HACKER_ACCOUNT, INCIDENT_AMOUNT);
    usdc.mint(address(zklighter), 100_000_000 * 10 ** 6);

    // Both proxies are upgraded through one gatekeeper, as in production
    gatekeeper = new UpgradeGatekeeper(securityCouncil, address(zklighterProxy));
    governanceProxy.transferMastership(address(gatekeeper));
    zklighterProxy.transferMastership(address(gatekeeper));
    gatekeeper.addUpgradeable(address(governanceProxy));
    gatekeeper.addUpgradeable(address(zklighterProxy));
  }

  // ---------------------------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------------------------

  /// @dev Full gatekeeper flow with the Security Council cutting the notice period.
  /// A zero target leaves that contract on its current implementation
  function _upgrade(address newGovernance, address newZkLighter) internal {
    address[] memory targets = new address[](2);
    targets[0] = newGovernance;
    targets[1] = newZkLighter;
    gatekeeper.startUpgrade(targets);
    vm.prank(securityCouncil);
    gatekeeper.cutUpgradeNoticePeriod(block.timestamp);
    assertTrue(gatekeeper.startPreparation());

    bytes[] memory params = new bytes[](2);
    params[0] = "";
    params[1] = abi.encode(address(0), address(0), address(0), address(0));
    gatekeeper.finishUpgrade(params);
  }

  function _upgradeGovernance() internal returns (address newImplementation) {
    newImplementation = address(new Governance());
    _upgrade(newImplementation, address(0));
    assertEq(governanceProxy.getTarget(), newImplementation);
  }

  function _startPauseGuardianPause(uint64 duration) internal {
    vm.prank(pauseGuardian);
    governance.pauseSystem(duration);
  }

  function _startEmergencyPause(uint64 duration) internal {
    vm.prank(emergencyGuardian);
    governance.emergencyPauseSystem(duration);
  }

  function _assertPauseStatesAreZero() internal view {
    (uint64 startedAt, uint64 expiresAt, uint64 cooldownEndsAt) = governance.pauseGuardianState();
    assertEq(startedAt, 0);
    assertEq(expiresAt, 0);
    assertEq(cooldownEndsAt, 0);
    (startedAt, expiresAt, cooldownEndsAt) = governance.emergencyGuardianState();
    assertEq(startedAt, 0);
    assertEq(expiresAt, 0);
    assertEq(cooldownEndsAt, 0);
    assertFalse(governance.pauseGuardianPaused());
    assertFalse(governance.emergencyGuardianPaused());
    governance.requireUnpaused();
  }

  // ---------------------------------------------------------------------------------------------
  // The pause is lifted
  // ---------------------------------------------------------------------------------------------

  function test_upgrade_clearsActiveEmergencyPause() public {
    _startEmergencyPause(24 hours);
    vm.warp(block.timestamp + 1 hours);
    vm.expectRevert(EmergencyPause.Paused.selector);
    governance.requireUnpaused();

    _upgradeGovernance();
    _assertPauseStatesAreZero();
  }

  function test_upgrade_clearsActivePauseGuardianPause() public {
    _startPauseGuardianPause(24 hours);
    vm.warp(block.timestamp + 1 hours);
    vm.expectRevert(EmergencyPause.Paused.selector);
    governance.requireUnpaused();

    _upgradeGovernance();
    _assertPauseStatesAreZero();
  }

  function test_upgrade_clearsBothPausesAtOnce() public {
    _startPauseGuardianPause(24 hours);
    _startEmergencyPause(72 hours);

    _upgradeGovernance();
    _assertPauseStatesAreZero();
  }

  function test_upgrade_clearsPauseInTheSameBlockItStarted() public {
    _startEmergencyPause(24 hours);
    _upgradeGovernance();
    _assertPauseStatesAreZero();
  }

  /// @dev The governor itself cannot lift an emergency pause before 24 hours; the upgrade can
  function test_upgrade_clearsPauseThatGovernorCannotYetEnd() public {
    _startEmergencyPause(24 hours);
    vm.warp(block.timestamp + 23 hours);
    vm.prank(governor);
    vm.expectRevert(EmergencyPause.MinimumPauseDurationNotElapsed.selector);
    governance.emergencyUnpauseSystem();

    _upgradeGovernance();
    _assertPauseStatesAreZero();
  }

  function test_upgrade_clearsExtendedPause() public {
    _startEmergencyPause(24 hours);
    (uint64 startedAt, , ) = governance.emergencyGuardianState();
    vm.prank(emergencyGuardian);
    governance.extendEmergencyPause(startedAt + 72 hours);

    _upgradeGovernance();
    _assertPauseStatesAreZero();
  }

  function test_upgrade_clearsCooldownOfExpiredPause() public {
    _startPauseGuardianPause(2 hours);
    _startEmergencyPause(24 hours);
    vm.warp(block.timestamp + 25 hours);
    governance.requireUnpaused();

    vm.prank(pauseGuardian);
    vm.expectRevert(EmergencyPause.PauseCooldownActive.selector);
    governance.pauseSystem(2 hours);

    _upgradeGovernance();
    _assertPauseStatesAreZero();
  }

  function test_upgrade_clearsCooldownOfPauseEndedByGovernor() public {
    _startPauseGuardianPause(24 hours);
    vm.warp(block.timestamp + 2 hours);
    vm.prank(governor);
    governance.unpauseSystem();
    (, , uint64 cooldownEndsAt) = governance.pauseGuardianState();
    assertGt(cooldownEndsAt, block.timestamp);

    _upgradeGovernance();
    _assertPauseStatesAreZero();
  }

  function test_upgrade_withoutAnyPauseIsANoOp() public {
    vm.recordLogs();
    _upgradeGovernance();
    _assertPauseStatesAreZero();

    bytes32 pauseEnded = keccak256("PauseEnded(uint8,address,uint64)");
    Vm.Log[] memory logs = vm.getRecordedLogs();
    for (uint256 i = 0; i < logs.length; ++i) {
      assertTrue(logs[i].topics[0] != pauseEnded, "no PauseEnded without a pause");
    }
  }

  function test_upgrade_emitsPauseEndedForEachActivePause() public {
    _startPauseGuardianPause(24 hours);
    _startEmergencyPause(24 hours);

    address[] memory targets = new address[](2);
    targets[0] = address(new Governance());
    gatekeeper.startUpgrade(targets);
    vm.prank(securityCouncil);
    gatekeeper.cutUpgradeNoticePeriod(block.timestamp);
    gatekeeper.startPreparation();

    vm.expectEmit(true, true, false, true, address(governanceProxy));
    emit EmergencyPause.PauseEnded(EmergencyPause.PauseTier.PauseGuardian, address(gatekeeper), 0);
    vm.expectEmit(true, true, false, true, address(governanceProxy));
    emit EmergencyPause.PauseEnded(EmergencyPause.PauseTier.EmergencyGuardian, address(gatekeeper), 0);
    gatekeeper.finishUpgrade(new bytes[](2));
  }

  function test_upgrade_canBeRepeated() public {
    _startEmergencyPause(24 hours);
    _upgradeGovernance();
    _startEmergencyPause(24 hours);
    _upgradeGovernance();
    _assertPauseStatesAreZero();
  }

  function testFuzz_upgrade_clearsAnyPauseAtAnyTime(
    uint64 pauseDuration,
    uint64 emergencyDuration,
    uint64 elapsed,
    bool withPause,
    bool withEmergency
  ) public {
    if (withPause) {
      _startPauseGuardianPause(uint64(bound(pauseDuration, 2 hours, 24 hours)));
    }
    if (withEmergency) {
      _startEmergencyPause(uint64(bound(emergencyDuration, 24 hours, 72 hours)));
    }
    vm.warp(block.timestamp + bound(elapsed, 0, 30 days));

    _upgradeGovernance();
    _assertPauseStatesAreZero();
  }

  // ---------------------------------------------------------------------------------------------
  // Nothing else changes
  // ---------------------------------------------------------------------------------------------

  function test_upgrade_keepsGuardiansGovernorValidatorsAndUSDC() public {
    _startPauseGuardianPause(24 hours);
    _startEmergencyPause(24 hours);
    _upgradeGovernance();

    assertEq(governance.pauseGuardian(), pauseGuardian);
    assertEq(governance.emergencyGuardian(), emergencyGuardian);
    assertEq(governance.networkGovernor(), governor);
    assertEq(address(governance.usdc()), address(usdc));
    governance.isActiveValidator(validator);
    governance.requireGovernor(governor);
    vm.expectRevert(IGovernance.ZkLighter_Governance_InvalidValidator.selector);
    governance.isActiveValidator(address(this));
  }

  function test_upgrade_keepsGuardianStorageSlotsBitForBit() public {
    bytes32 base = 0x48e77f48bcec852db4f14007725dea1c391e1f193bc893e97e7b067e5ea1ab00;
    _startPauseGuardianPause(24 hours);
    _startEmergencyPause(24 hours);
    bytes32 pauseGuardianSlot = vm.load(address(governanceProxy), base);
    bytes32 emergencyGuardianSlot = vm.load(address(governanceProxy), bytes32(uint256(base) + 1));
    assertTrue(vm.load(address(governanceProxy), bytes32(uint256(base) + 2)) != bytes32(0));
    assertTrue(vm.load(address(governanceProxy), bytes32(uint256(base) + 3)) != bytes32(0));

    _upgradeGovernance();

    assertEq(vm.load(address(governanceProxy), base), pauseGuardianSlot);
    assertEq(vm.load(address(governanceProxy), bytes32(uint256(base) + 1)), emergencyGuardianSlot);
    assertEq(vm.load(address(governanceProxy), bytes32(uint256(base) + 2)), bytes32(0));
    assertEq(vm.load(address(governanceProxy), bytes32(uint256(base) + 3)), bytes32(0));
  }

  function test_upgrade_guardiansCanPauseAgainImmediately() public {
    _startPauseGuardianPause(24 hours);
    _startEmergencyPause(24 hours);
    _upgradeGovernance();

    _startPauseGuardianPause(2 hours);
    _startEmergencyPause(24 hours);
    assertTrue(governance.pauseGuardianPaused());
    assertTrue(governance.emergencyGuardianPaused());
    vm.expectRevert(EmergencyPause.Paused.selector);
    governance.requireUnpaused();
  }

  function test_upgrade_nonGuardiansStillCannotPause() public {
    _startEmergencyPause(24 hours);
    _upgradeGovernance();

    vm.expectRevert(EmergencyPause.NotPauseGuardian.selector);
    governance.pauseSystem(2 hours);
    vm.expectRevert(EmergencyPause.NotEmergencyGuardian.selector);
    governance.emergencyPauseSystem(24 hours);
  }

  // ---------------------------------------------------------------------------------------------
  // Only the upgrade can do it
  // ---------------------------------------------------------------------------------------------

  function test_upgrade_cannotBeCalledThroughTheProxy() public {
    _startEmergencyPause(24 hours);
    address[4] memory callers = [governor, emergencyGuardian, HACKER_ADDRESS, address(this)];
    for (uint256 i = 0; i < callers.length; ++i) {
      vm.prank(callers[i]);
      vm.expectRevert(bytes("upg11"));
      governance.upgrade("");
    }
    assertTrue(governance.emergencyGuardianPaused());
  }

  function test_upgrade_cannotBeCalledOnTheImplementation() public {
    Governance implementation = Governance(governanceProxy.getTarget());
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyProxyCanCallUpgrade.selector);
    implementation.upgrade("");
  }

  function test_upgrade_onlyGatekeeperCanUpgradeTheProxy() public {
    _startEmergencyPause(24 hours);
    address newImplementation = address(new Governance());
    vm.expectRevert(bytes("1c"));
    governanceProxy.upgradeTarget(newImplementation, "");
    vm.prank(governor);
    vm.expectRevert(bytes("1c"));
    governanceProxy.upgradeTarget(newImplementation, "");
    assertTrue(governance.emergencyGuardianPaused());
  }

  /// @dev Governance must get a new target in the upgrade, otherwise the pause stays
  function test_upgrade_withoutGovernanceTargetDoesNotClearThePause() public {
    _startEmergencyPause(24 hours);
    _upgrade(address(0), address(0));

    assertTrue(governance.emergencyGuardianPaused());
    vm.expectRevert(EmergencyPause.Paused.selector);
    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT);
  }

  /// @dev ZkLighter.upgrade only accepts the parameters committed to in the implementation, and they are not
  /// the all-zero ones. A rejected ZkLighter target reverts the whole upgrade, Governance included
  function test_upgrade_zkLighterTargetWithUncommittedParametersRevertsWholeUpgrade() public {
    _startEmergencyPause(24 hours);
    address oldGovernance = governanceProxy.getTarget();

    address[] memory targets = new address[](2);
    targets[0] = address(new Governance());
    targets[1] = address(new ZkLighterTest());
    gatekeeper.startUpgrade(targets);
    vm.prank(securityCouncil);
    gatekeeper.cutUpgradeNoticePeriod(block.timestamp);
    gatekeeper.startPreparation();

    bytes[] memory params = new bytes[](2);
    params[1] = abi.encode(address(0), address(0), address(0), address(0));
    vm.expectRevert(bytes("ufu11"));
    gatekeeper.finishUpgrade(params);

    assertEq(governanceProxy.getTarget(), oldGovernance);
    assertTrue(governance.emergencyGuardianPaused());
  }

  // ---------------------------------------------------------------------------------------------
  // Effect on ZkLighter
  // ---------------------------------------------------------------------------------------------

  function test_upgrade_withdrawalsResumeAndHackerStaysBlocked() public {
    _startEmergencyPause(24 hours);
    vm.warp(block.timestamp + 3 hours);

    vm.expectRevert(EmergencyPause.Paused.selector);
    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT);

    _upgradeGovernance();
    _assertPauseStatesAreZero();

    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT);
    assertEq(usdc.balanceOf(VICTIM_ADDRESS), INCIDENT_AMOUNT);

    vm.expectRevert(bytes(""));
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, USDC, INCIDENT_AMOUNT);
    assertEq(usdc.balanceOf(HACKER_ADDRESS), 0);
  }

  function test_upgrade_pauseStartedAfterUpgradeStillBlocksZkLighter() public {
    _startEmergencyPause(24 hours);
    _upgradeGovernance();

    _startPauseGuardianPause(2 hours);
    vm.expectRevert(EmergencyPause.Paused.selector);
    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT);

    vm.warp(block.timestamp + 2 hours);
    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT);
    assertEq(usdc.balanceOf(VICTIM_ADDRESS), INCIDENT_AMOUNT);
  }

  function test_upgrade_blockedInDesertMode() public {
    _startEmergencyPause(24 hours);
    zklighter.setDesertMode(true);

    address[] memory targets = new address[](2);
    targets[0] = address(new Governance());
    gatekeeper.startUpgrade(targets);
    vm.prank(securityCouncil);
    gatekeeper.cutUpgradeNoticePeriod(block.timestamp);
    gatekeeper.startPreparation();

    bytes[] memory params = new bytes[](2);
    params[1] = abi.encode(address(0), address(0), address(0), address(0));
    vm.expectRevert(bytes("fpu13"));
    gatekeeper.finishUpgrade(params);
    assertTrue(governance.emergencyGuardianPaused());
  }
}
