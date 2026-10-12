// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";

import {EmergencyPause} from "../contracts/EmergencyPause.sol";
import {GovernanceTest} from "../contracts/test/GovernanceTest.sol";
import {IGovernance} from "../contracts/interfaces/IGovernance.sol";
import {OwnableERC20} from "../contracts/test/OwnableERC20.sol";
import {Proxy} from "../contracts/proxy/Proxy.sol";

contract EmergencyPauseTests is Test {
  address internal pauseGuardian = address(0x9A1);
  address internal emergencyGuardian = address(0x9A2);

  GovernanceTest internal governance;

  function setUp() public {
    OwnableERC20 usdc = new OwnableERC20("USDC", "USDC", 6);
    Proxy proxy = new Proxy(address(new GovernanceTest()), abi.encode(address(this), address(usdc)));
    governance = GovernanceTest(address(proxy));
    governance.overrideGuardians(pauseGuardian, emergencyGuardian);
    vm.warp(1_000_000);
  }

  function test_initializeGuardiansRevertsWhenBothAlreadySet() public {
    vm.expectRevert(GovernanceTest.GuardiansAlreadyInitialized.selector);
    governance.overrideGuardians(address(0x9B1), address(0x9B2));

    assertEq(governance.pauseGuardian(), pauseGuardian);
    assertEq(governance.emergencyGuardian(), emergencyGuardian);
  }

  function test_initializeGuardiansRevertsWhenOnlyEmergencyGuardianSet() public {
    governance.setPauseGuardian(address(0));
    assertEq(governance.pauseGuardian(), address(0));

    vm.expectRevert(GovernanceTest.GuardiansAlreadyInitialized.selector);
    governance.overrideGuardians(address(0x9B1), address(0x9B2));

    assertEq(governance.pauseGuardian(), address(0));
    assertEq(governance.emergencyGuardian(), emergencyGuardian);
  }

  function test_governorSetsEmergencyGuardian() public {
    address newEmergencyGuardian = address(0x9A3);
    governance.setEmergencyGuardian(newEmergencyGuardian);
    assertEq(governance.emergencyGuardian(), newEmergencyGuardian);

    vm.prank(emergencyGuardian);
    vm.expectRevert(EmergencyPause.NotEmergencyGuardian.selector);
    governance.emergencyPauseSystem(24 hours);

    vm.prank(newEmergencyGuardian);
    governance.emergencyPauseSystem(24 hours);
    assertTrue(governance.emergencyGuardianPaused());
  }

  function test_emergencyGuardianCannotSetEmergencyGuardian() public {
    vm.prank(emergencyGuardian);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    governance.setEmergencyGuardian(address(0x9A3));

    assertEq(governance.emergencyGuardian(), emergencyGuardian);
  }

  function test_pauseGuardianCannotSetPauseGuardian() public {
    vm.prank(pauseGuardian);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    governance.setPauseGuardian(address(0x9A3));

    vm.prank(emergencyGuardian);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    governance.setPauseGuardian(address(0x9A3));

    assertEq(governance.pauseGuardian(), pauseGuardian);
  }

  function test_changeGovernorMovesGuardianAndUnpauseRights() public {
    address newGovernor = address(0x6A1);
    governance.changeGovernor(newGovernor);

    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    governance.setPauseGuardian(address(0x9A3));

    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    governance.setEmergencyGuardian(address(0x9A3));

    vm.prank(newGovernor);
    governance.setPauseGuardian(address(0x9A3));
    assertEq(governance.pauseGuardian(), address(0x9A3));

    vm.prank(newGovernor);
    governance.setEmergencyGuardian(address(0x9A4));
    assertEq(governance.emergencyGuardian(), address(0x9A4));

    vm.prank(address(0x9A3));
    governance.pauseSystem(4 hours);
    vm.prank(address(0x9A4));
    governance.emergencyPauseSystem(72 hours);

    vm.warp(block.timestamp + 2 hours);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    governance.unpauseSystem();
    vm.prank(newGovernor);
    governance.unpauseSystem();

    vm.warp(block.timestamp + 22 hours);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    governance.emergencyUnpauseSystem();
    vm.prank(newGovernor);
    governance.emergencyUnpauseSystem();

    assertFalse(governance.pauseGuardianPaused());
    assertFalse(governance.emergencyGuardianPaused());
  }

  function test_governorUnpausesPauseGuardianPause() public {
    vm.prank(pauseGuardian);
    governance.pauseSystem(4 hours);

    vm.warp(block.timestamp + 2 hours);
    governance.unpauseSystem();

    assertFalse(governance.pauseGuardianPaused());
  }

  function test_pauseGuardianCannotUnpausePauseGuardianPause() public {
    vm.prank(pauseGuardian);
    governance.pauseSystem(4 hours);

    vm.warp(block.timestamp + 2 hours);
    vm.prank(pauseGuardian);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    governance.unpauseSystem();

    assertTrue(governance.pauseGuardianPaused());
  }

  function test_governorUnpausesEmergencyPauseAfterMinimumDuration() public {
    vm.prank(emergencyGuardian);
    governance.emergencyPauseSystem(72 hours);

    vm.warp(block.timestamp + 24 hours - 1);
    vm.expectRevert(EmergencyPause.MinimumPauseDurationNotElapsed.selector);
    governance.emergencyUnpauseSystem();

    vm.warp(block.timestamp + 1);
    governance.emergencyUnpauseSystem();

    assertFalse(governance.emergencyGuardianPaused());
    (, , uint64 cooldownEndsAt) = governance.emergencyGuardianState();
    assertEq(cooldownEndsAt, uint64(block.timestamp + 7 days));
  }

  function test_emergencyGuardianCannotUnpauseEmergencyPause() public {
    vm.prank(emergencyGuardian);
    governance.emergencyPauseSystem(72 hours);

    vm.warp(block.timestamp + 24 hours);
    vm.prank(emergencyGuardian);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    governance.emergencyUnpauseSystem();

    assertTrue(governance.emergencyGuardianPaused());
  }

  function test_pauseGuardianCannotUnpauseEmergencyPause() public {
    vm.prank(emergencyGuardian);
    governance.emergencyPauseSystem(72 hours);

    vm.warp(block.timestamp + 24 hours);
    vm.prank(pauseGuardian);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    governance.emergencyUnpauseSystem();
  }
}
