// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";

import {AdditionalZkLighter} from "../contracts/AdditionalZkLighter.sol";
import {Governance} from "../contracts/Governance.sol";
import {Storage} from "../contracts/Storage.sol";
import {ZkLighterTest} from "../contracts/test/ZkLighterTest.sol";
import {DesertVerifierTest} from "../contracts/test/DesertVerifierTest.sol";
import {OwnableERC20} from "../contracts/test/OwnableERC20.sol";
import {ZkLighterVerifierTest} from "../contracts/test/ZkLighterVerifierTest.sol";
import {IZkLighter} from "../contracts/interfaces/IZkLighter.sol";
import {TxTypes} from "../contracts/lib/TxTypes.sol";
import {Proxy} from "../contracts/proxy/Proxy.sol";

contract ProxyTests is Test {
  bytes32 internal constant GENESIS_STATE_ROOT = 0x9138b1881fc37551cd6da339fd8b968bae7b3cc36ee78c857c4c0e9b923720dc;
  bytes32 internal constant GENESIS_VALIDIUM_ROOT = 0xa96f8fe3b07701bc823ccaa874bb6c07e71823cf52c67eac12283b2ac142feac;

  OwnableERC20 internal usdc;
  Governance internal governanceImplementation;
  ZkLighterVerifierTest internal verifierImplementation;
  ZkLighterTest internal zklighterImplementation;
  AdditionalZkLighter internal additionalZkLighter;
  DesertVerifierTest internal desertVerifier;

  Proxy internal governanceProxy;
  Proxy internal verifierProxy;
  Proxy internal zklighterProxy;

  Governance internal governance;
  ZkLighterVerifierTest internal verifier;
  ZkLighterTest internal zklighter;

  address internal newGovernor = address(0xBEEF);
  address internal pauseGuardian = address(0x9A1);
  address internal emergencyGuardian = address(0x9A2);

  function setUp() public {
    usdc = new OwnableERC20("USDC", "USDC", 6);
    governanceImplementation = new Governance();
    verifierImplementation = new ZkLighterVerifierTest();
    zklighterImplementation = new ZkLighterTest();
    additionalZkLighter = new AdditionalZkLighter();
    desertVerifier = new DesertVerifierTest();

    governanceProxy = new Proxy(address(governanceImplementation), abi.encode(address(this), address(usdc)));
    governance = Governance(address(governanceProxy));
    governance.setValidator(address(this), true);

    verifierProxy = new Proxy(address(verifierImplementation), "");
    verifier = ZkLighterVerifierTest(address(verifierProxy));

    zklighterProxy = new Proxy(
      address(zklighterImplementation),
      abi.encode(
        address(governance),
        address(verifier),
        address(additionalZkLighter),
        address(desertVerifier),
        GENESIS_STATE_ROOT,
        GENESIS_VALIDIUM_ROOT
      )
    );
    zklighter = ZkLighterTest(payable(address(zklighterProxy)));
  }

  function test_proxyStoresTargets() public view {
    assertEq(governanceProxy.getTarget(), address(governanceImplementation));
    assertEq(verifierProxy.getTarget(), address(verifierImplementation));
    assertEq(zklighterProxy.getTarget(), address(zklighterImplementation));
  }

  function test_upgradeGovernanceTarget() public {
    Governance newImplementation = new Governance();

    governanceProxy.upgradeTarget(address(newImplementation), abi.encode());
    governance.setPauseGuardian(address(pauseGuardian));
    governance.setEmergencyGuardian(address(emergencyGuardian));

    assertEq(governanceProxy.getTarget(), address(newImplementation));
    assertEq(governance.networkGovernor(), address(this));
    assertEq(address(governance.usdc()), address(usdc));
    assertEq(governance.pauseGuardian(), pauseGuardian);
    assertEq(governance.emergencyGuardian(), emergencyGuardian);
  }

  function test_governanceStorageLayoutMatchesPreEmergencyPause() public {
    governance.setPauseGuardian(address(0x9A1));

    assertEq(address(uint160(uint256(vm.load(address(governanceProxy), bytes32(uint256(51)))))), address(usdc));
    assertEq(address(uint160(uint256(vm.load(address(governanceProxy), bytes32(uint256(52)))))), address(this));
    assertEq(vm.load(address(governanceProxy), bytes32(uint256(53))), bytes32(0));

    bytes32 location = keccak256(abi.encode(uint256(keccak256("zklighter.storage.EmergencyPause")) - 1)) & ~bytes32(uint256(0xff));
    assertEq(location, 0x48e77f48bcec852db4f14007725dea1c391e1f193bc893e97e7b067e5ea1ab00);
    assertEq(address(uint160(uint256(vm.load(address(governanceProxy), location)))), address(0x9A1));
    assertEq(governance.pauseGuardian(), address(0x9A1));
  }

  function test_upgradeVerifierTarget() public {
    ZkLighterVerifierTest newImplementation = new ZkLighterVerifierTest();

    verifierProxy.upgradeTarget(address(newImplementation), "");

    assertEq(verifierProxy.getTarget(), address(newImplementation));
    assertTrue(ZkLighterVerifierTest(address(verifierProxy)).Verify("proof", _publicInputs()));
  }

  function test_upgradeTargetRejectsNonMaster() public {
    Governance newImplementation = new Governance();

    vm.prank(address(0xBAD));
    vm.expectRevert(bytes("1c"));
    governanceProxy.upgradeTarget(address(newImplementation), "");
  }

  function test_delegateGovernanceCall() public {
    governance.changeGovernor(newGovernor);

    assertEq(governance.networkGovernor(), newGovernor);
  }

  function test_delegateVerifierCall() public view {
    assertTrue(verifier.Verify("proof", _publicInputs()));
  }

  function test_delegateDepositCall() public {
    vm.expectRevert(bytes("ERC20: insufficient allowance"));
    zklighter.deposit(address(0xCAFE), 3, TxTypes.RouteType.Perps, 1_000_000);
  }

  function test_delegateRevertBatchesCall() public {
    Storage.StoredBatchInfo memory genesisBatch = Storage.StoredBatchInfo({
      batchNumber: 0,
      endBlockNumber: 0,
      batchSize: 0,
      startTimestamp: 0,
      endTimestamp: 0,
      priorityRequestCount: 0,
      prefixPriorityRequestHash: bytes32(0),
      onChainOperationsHash: bytes32(0),
      stateRoot: GENESIS_STATE_ROOT,
      validiumRoot: GENESIS_VALIDIUM_ROOT,
      commitment: bytes32(0)
    });

    zklighter.revertBatches(new Storage.StoredBatchInfo[](0), genesisBatch);
  }

  function test_proxyInterceptsGovernanceUpgrade() public {
    vm.expectRevert(bytes("upg11"));
    governance.upgrade(abi.encode(address(0xA1)));
  }

  function test_proxyInterceptsVerifierUpgrade() public {
    vm.expectRevert(bytes("upg11"));
    verifier.upgrade(abi.encode(address(0xA2)));
  }

  function test_proxyInterceptsZkLighterUpgrade() public {
    vm.expectRevert(bytes("upg11"));
    zklighter.upgrade(abi.encode(address(0xA3)));
  }

  function test_zkLighterProxyRetainsImplementationTarget() public view {
    assertEq(zklighterProxy.getTarget(), address(zklighterImplementation));
  }

  function test_upgradeZkLighterSkipped() public {
    vm.skip(true, "Preserves the skipped Hardhat upgrade case");
  }

  function test_directImplementationCallsAreRejected() public {
    bytes memory upgradeParameters = abi.encode(address(additionalZkLighter), address(desertVerifier));

    vm.expectRevert(IZkLighter.ZkLighter_OnlyProxyCanCallUpgrade.selector);
    zklighterImplementation.upgrade(upgradeParameters);

    vm.expectRevert(IZkLighter.ZkLighter_ImplCantDelegateToAddl.selector);
    zklighterImplementation.deposit(address(0xCAFE), 3, TxTypes.RouteType.Perps, 10);
  }

  function _publicInputs() internal pure returns (uint256[] memory inputs) {
    inputs = new uint256[](1);
    inputs[0] = 1;
  }
}
