// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ZkLighterTest} from "../contracts/test/ZkLighterTest.sol";
import {ZkLighter} from "../contracts/ZkLighter.sol";
import {IZkLighter} from "../contracts/interfaces/IZkLighter.sol";
import {Storage} from "../contracts/Storage.sol";
import {GovernanceTest} from "../contracts/test/GovernanceTest.sol";
import {IGovernance} from "../contracts/interfaces/IGovernance.sol";
import {IEvents} from "../contracts/interfaces/IEvents.sol";
import {ZkLighterVerifierTest} from "../contracts/test/ZkLighterVerifierTest.sol";
import {TxTypes} from "../contracts/lib/TxTypes.sol";

/// System account tests for ZkLighter contract
contract ZkLighterSystemTests is Test {
  ZkLighterTest zklighter;
  GovernanceTest governance;

  function setUp() public {
    zklighter = new ZkLighterTest();
    governance = new GovernanceTest();

    governance.overrideNetworkGovernor(address(0x31));

    zklighter.setGovernanceAddress(address(governance));
  }

  function test_setTreasury_success() public {
    vm.expectEmit();
    emit IEvents.TreasuryUpdate(address(0x32)); // expect emit log similar to this

    vm.prank(address(0x31));
    zklighter.setTreasury(address(0x32));
    assertEq(zklighter.treasury(), address(0x32), "Treasury should be updated");
  }

  function test_setTreasury_fail_not_governor() public {
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    vm.prank(address(0x62));
    zklighter.setTreasury(address(0x32));
  }

  function test_setTreasury_fail_zero_address() public {
    vm.expectRevert(IZkLighter.ZkLighter_TreasuryCannotBeZero.selector);
    vm.prank(address(0x31));
    zklighter.setTreasury(address(0));
  }

  function test_setTreasury_fail_inuse_account() public {
    zklighter.setAddressToAccountIndex(address(0x32), 5);

    vm.expectRevert(IZkLighter.ZkLighter_TreasuryCannotBeInUse.selector);
    vm.prank(address(0x31));
    zklighter.setTreasury(address(0x32));
  }

  function test_setTreasury_fail_also_insurance_fund() public {
    vm.prank(address(0x31));
    zklighter.setInsuranceFundOperator(address(0x32));

    vm.expectRevert(IZkLighter.ZkLighter_TreasuryCannotBeInUse.selector);
    vm.prank(address(0x31));
    zklighter.setTreasury(address(0x32));
  }

  function test_setInsuranceFundOperator_success() public {
    vm.expectEmit();
    emit IEvents.InsuranceFundOperatorUpdate(address(0x32)); // expect emit log similar to this

    vm.prank(address(0x31));
    zklighter.setInsuranceFundOperator(address(0x32));
    assertEq(zklighter.insuranceFundOperator(), address(0x32), "InsuranceFundOperator should be updated");
  }

  function test_setInsuranceFundOperator_fail_not_governor() public {
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    vm.prank(address(0x62));
    zklighter.setInsuranceFundOperator(address(0x32));
  }

  function test_setInsuranceFundOperator_fail_zero_address() public {
    vm.expectRevert(IZkLighter.ZkLighter_InsuranceFundOperatorCannotBeZero.selector);
    vm.prank(address(0x31));
    zklighter.setInsuranceFundOperator(address(0));
  }

  function test_setInsuranceFundOperator_fail_inuse_account() public {
    zklighter.setAddressToAccountIndex(address(0x32), 5);

    vm.expectRevert(IZkLighter.ZkLighter_InsuranceFundOperatorCannotBeInUse.selector);
    vm.prank(address(0x31));
    zklighter.setInsuranceFundOperator(address(0x32));
  }

  function test_setInsuranceFundOperator_fail_also_treasury() public {
    vm.prank(address(0x31));
    zklighter.setTreasury(address(0x32));

    vm.expectRevert(IZkLighter.ZkLighter_InsuranceFundOperatorCannotBeInUse.selector);
    vm.prank(address(0x31));
    zklighter.setInsuranceFundOperator(address(0x32));
  }
}
