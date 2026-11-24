// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";

import {ZkLighterTest} from "../contracts/test/ZkLighterTest.sol";
import {AdditionalZkLighter} from "../contracts/AdditionalZkLighter.sol";
import {Storage} from "../contracts/Storage.sol";
import {OwnableERC20} from "../contracts/test/OwnableERC20.sol";
import {GovernanceTest} from "../contracts/test/GovernanceTest.sol";
import {EmergencyPause} from "../contracts/EmergencyPause.sol";
import {IEvents} from "../contracts/interfaces/IEvents.sol";
import {ZkLighterVerifierTest} from "../contracts/test/ZkLighterVerifierTest.sol";
import {DesertVerifierTest} from "../contracts/test/DesertVerifierTest.sol";
import {TxTypes} from "../contracts/lib/TxTypes.sol";
import {IZkLighter} from "../contracts/interfaces/IZkLighter.sol";

contract ZkLighterRecoveryHarness is ZkLighterTest {
  /// @dev Places the rollup at an arbitrary batch height with nothing pending
  function setBatchHeight(uint64 batchNumber) external {
    committedBatchesCount = batchNumber;
    verifiedBatchesCount = batchNumber;
    executedBatchesCount = batchNumber;
    pendingOnChainBatchesCount = 0;
  }
}

/// Tests for the Security Council intervention that credits the hacker account's (769455) USDC
/// withdrawals to the drained account (769566) and blocks payouts to the hacker L1 address
contract ZkLighterSecurityCouncilRecoveryTests is Test {
  uint48 internal constant HACKER_ACCOUNT = 769455;
  address internal constant HACKER_ADDRESS = 0xb3fffca23d4444eE73349825ACD84f7b5020e387;
  uint48 internal constant VICTIM_ACCOUNT = 769566;
  address internal constant VICTIM_ADDRESS = 0x66Cf2f85115CC20bF439720927C1f93De9672068;

  uint64 internal constant LAST_REDIRECTED_BATCH = 269800;
  uint64 internal constant INCIDENT_BATCH = 269214;
  // 5,096,588.024995 USDC
  uint64 internal constant INCIDENT_AMOUNT = 5_096_588_024_995;

  uint16 internal constant ETH = 1;
  uint16 internal constant LIT = 2;
  uint16 internal constant USDC = 3;
  uint256 internal constant ETH_TICK = 10 ** 10;
  uint256 internal constant LIT_TICK = 10 ** 12;

  uint48 internal constant OTHER_ACCOUNT = 1234;
  address internal constant OTHER_ADDRESS = address(0x1234);

  struct WithdrawLog {
    bool legacyUSDCType;
    uint48 accountIndex;
    uint16 assetIndex;
    uint64 amount;
  }

  OwnableERC20 internal usdc;
  OwnableERC20 internal lit;
  ZkLighterRecoveryHarness internal zklighter;
  GovernanceTest internal governance;
  DesertVerifierTest internal desertVerifier;

  bytes internal blobPubData;
  Storage.StoredBatchInfo internal lastStoredBatch;

  function setUp() public {
    zklighter = new ZkLighterRecoveryHarness();
    governance = new GovernanceTest();
    usdc = new OwnableERC20("USD Coin", "USDC", 6);
    lit = new OwnableERC20("Lighter", "LIT", 18);

    zklighter.setAdditionalZkLighterAddress(address(new AdditionalZkLighter()));
    governance.overrideUSDCAddress(usdc);
    governance.overrideValidator(address(this), true);
    governance.overrideNetworkGovernor(address(this));
    zklighter.setGovernanceAddress(address(governance));
    zklighter.setVerifierAddress(address(new ZkLighterVerifierTest()));
    desertVerifier = new DesertVerifierTest();
    zklighter.setDesertVerifierAddress(address(desertVerifier));

    blobPubData = hex"0071d46f9b04e49c1c89863e820571ec1fef14467de4c91087d67518e8a3f42c203c6250bad14238cb26c02973200ef5cfed332e01508064fe36cfc021d5503525b8900a6dd9bd485d615b1cc6a6dbb1bafc886aa27338b981c9edb33d77b66edbf698abe5e7e75de6bb0bf53dba2ce36990e8d5db1a9a08078fcc8f9315b20f427ce82135502c725c89380ddf685d7f00890d5d24824b818b0bb790ec49f9c12c";

    zklighter.setAddressToAccountIndex(HACKER_ADDRESS, HACKER_ACCOUNT);
    zklighter.setAddressToAccountIndex(VICTIM_ADDRESS, VICTIM_ACCOUNT);
    zklighter.setAddressToAccountIndex(OTHER_ADDRESS, OTHER_ACCOUNT);

    vm.deal(address(zklighter), 1_000 ether);
    usdc.mint(address(zklighter), 1_000_000_000 * 10 ** 6);
    lit.mint(address(zklighter), 1_000_000_000 * 10 ** 18);

    zklighter.registerDefaultAssetConfigs();
    zklighter.registerAssetConfig(LIT, address(lit), 1, 10 ** 6, uint128(LIT_TICK), (2 ** 50) - 1, 100);
  }

  // ---------------------------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------------------------

  function _log(bool legacyUSDCType, uint48 accountIndex, uint16 assetIndex, uint64 amount) internal pure returns (WithdrawLog memory) {
    return WithdrawLog({legacyUSDCType: legacyUSDCType, accountIndex: accountIndex, assetIndex: assetIndex, amount: amount});
  }

  function _one(WithdrawLog memory a) internal pure returns (WithdrawLog[] memory logs) {
    logs = new WithdrawLog[](1);
    logs[0] = a;
  }

  /// @dev Pub data and its hash exactly as the sequencer and the circuit produce them: with the account
  /// that signed the withdrawal, never the account the contract ends up crediting
  function _encode(WithdrawLog[] memory logs) internal pure returns (bytes memory pubData, bytes32 hash) {
    for (uint256 i = 0; i < logs.length; ++i) {
      if (logs[i].legacyUSDCType) {
        pubData = abi.encodePacked(pubData, TxTypes.OnChainPubDataType.USDCWithdraw, logs[i].accountIndex, logs[i].amount);
        hash = keccak256(abi.encodePacked(hash, TxTypes.OnChainPubDataType.USDCWithdraw, logs[i].accountIndex, logs[i].amount));
      } else {
        pubData = abi.encodePacked(pubData, TxTypes.OnChainPubDataType.Withdraw, logs[i].accountIndex, logs[i].assetIndex, logs[i].amount);
        hash = keccak256(abi.encodePacked(hash, TxTypes.OnChainPubDataType.Withdraw, logs[i].accountIndex, logs[i].assetIndex, logs[i].amount));
      }
    }
  }

  /// @dev Moves the rollup to `batchNumber - 1` unless it is already there
  function _positionBefore(uint64 batchNumber) internal {
    if (zklighter.committedBatchesCount() == batchNumber - 1 && lastStoredBatch.batchNumber == batchNumber - 1) {
      return;
    }
    lastStoredBatch = Storage.StoredBatchInfo({
      batchNumber: batchNumber - 1,
      endBlockNumber: batchNumber - 1,
      batchSize: 1,
      startTimestamp: 2,
      endTimestamp: 3,
      priorityRequestCount: 0,
      prefixPriorityRequestHash: bytes32(0),
      onChainOperationsHash: bytes32(0),
      stateRoot: keccak256(abi.encode("stateRoot", batchNumber - 1)),
      validiumRoot: keccak256(abi.encode("validiumRoot", batchNumber - 1)),
      commitment: bytes32(0)
    });
    zklighter.setBatchHeight(batchNumber - 1);
    zklighter.setStoredBatchHash(batchNumber - 1, keccak256(abi.encode(lastStoredBatch)));
  }

  /// @dev Commits and verifies batch `batchNumber` through the real entry points
  function _commitAndVerify(uint64 batchNumber, bytes32 onChainOperationsHash) internal returns (Storage.StoredBatchInfo memory stored) {
    _positionBefore(batchNumber);

    IZkLighter.CommitBatchInfo memory info = IZkLighter.CommitBatchInfo({
      endBlockNumber: lastStoredBatch.endBlockNumber + 1,
      batchSize: 1,
      startTimestamp: lastStoredBatch.endTimestamp,
      endTimestamp: lastStoredBatch.endTimestamp + 1,
      priorityRequestCount: 0,
      prefixPriorityRequestHash: bytes32(0),
      onChainOperationsHash: onChainOperationsHash,
      newStateRoot: keccak256(abi.encode("stateRoot", batchNumber)),
      newValidiumRoot: keccak256(abi.encode("validiumRoot", batchNumber)),
      pubdataCommitments: blobPubData
    });

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(info, lastStoredBatch);
    assertEq(zklighter.committedBatchesCount(), batchNumber, "committed batch number");

    stored = Storage.StoredBatchInfo({
      batchNumber: batchNumber,
      endBlockNumber: info.endBlockNumber,
      batchSize: info.batchSize,
      startTimestamp: info.startTimestamp,
      endTimestamp: info.endTimestamp,
      priorityRequestCount: 0,
      prefixPriorityRequestHash: bytes32(0),
      onChainOperationsHash: onChainOperationsHash,
      stateRoot: info.newStateRoot,
      validiumRoot: info.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Same shortcut as ZkLighter.t.sol: the commitment is not what is under test
    zklighter.setStoredBatchHash(batchNumber, keccak256(abi.encode(stored)));
    zklighter.verifyBatch(stored, hex"AAAA");
    lastStoredBatch = stored;
  }

  function _execute(Storage.StoredBatchInfo memory stored, bytes memory pubData) internal {
    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = stored;
    bytes[] memory pubDatas = new bytes[](1);
    pubDatas[0] = pubData;
    zklighter.executeBatches(batches, pubDatas);
  }

  function _runBatch(uint64 batchNumber, WithdrawLog[] memory logs) internal returns (Storage.StoredBatchInfo memory stored) {
    (bytes memory pubData, bytes32 hash) = _encode(logs);
    stored = _commitAndVerify(batchNumber, hash);
    _execute(stored, pubData);
    assertEq(zklighter.executedBatchesCount(), batchNumber, "executed batch number");
    assertEq(zklighter.pendingOnChainBatchesCount(), 0, "nothing left pending");
    assertEq(zklighter.stateRoot(), stored.stateRoot, "state root");
  }

  function _pending(uint16 assetIndex, address owner) internal view returns (uint128) {
    return zklighter.getPendingBalance(owner, assetIndex);
  }

  function _expectBlacklistRevert() internal {
    // _requireNotBlacklisted is a bare require, so it reverts with empty data
    vm.expectRevert(bytes(""));
  }

  // ---------------------------------------------------------------------------------------------
  // The incident, end to end
  // ---------------------------------------------------------------------------------------------

  function _incidentEndToEnd(bool legacyUSDCType) internal {
    uint256 contractBefore = usdc.balanceOf(address(zklighter));

    _runBatch(INCIDENT_BATCH, _one(_log(legacyUSDCType, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));

    assertEq(_pending(USDC, HACKER_ADDRESS), 0, "hacker must not be credited");
    assertEq(_pending(USDC, VICTIM_ADDRESS), INCIDENT_AMOUNT, "victim must be credited the full withdrawal");

    vm.prank(HACKER_ADDRESS);
    vm.expectRevert(IZkLighter.ZkLighter_InvalidWithdrawAmount.selector);
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, USDC, INCIDENT_AMOUNT);
    vm.prank(HACKER_ADDRESS);
    vm.expectRevert(IZkLighter.ZkLighter_InvalidWithdrawAmount.selector);
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, USDC, 1);

    vm.expectEmit(true, false, false, true, address(zklighter));
    emit IEvents.WithdrawPending(VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT);
    vm.prank(VICTIM_ADDRESS);
    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT);

    assertEq(usdc.balanceOf(VICTIM_ADDRESS), INCIDENT_AMOUNT, "victim L1 address receives the USDC");
    assertEq(usdc.balanceOf(HACKER_ADDRESS), 0, "hacker L1 address receives nothing");
    assertEq(usdc.balanceOf(address(zklighter)), contractBefore - INCIDENT_AMOUNT, "contract pays exactly the withdrawal");
    assertEq(_pending(USDC, VICTIM_ADDRESS), 0, "victim pending balance is cleared");
  }

  function test_incident_withdrawLog_creditsVictimAndPaysVictimAddress() public {
    _incidentEndToEnd(false);
  }

  function test_incident_usdcWithdrawLog_creditsVictimAndPaysVictimAddress() public {
    _incidentEndToEnd(true);
  }

  function test_incident_anyoneCanExecuteAndAnyoneCanTriggerVictimPayout() public {
    (bytes memory pubData, bytes32 hash) = _encode(_one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    Storage.StoredBatchInfo memory stored = _commitAndVerify(INCIDENT_BATCH, hash);

    // The hacker executing the batch himself changes nothing
    vm.prank(HACKER_ADDRESS);
    _execute(stored, pubData);
    assertEq(_pending(USDC, HACKER_ADDRESS), 0);
    assertEq(_pending(USDC, VICTIM_ADDRESS), INCIDENT_AMOUNT);

    // A third party, the hacker included, can only push the funds to the victim's own address
    vm.prank(HACKER_ADDRESS);
    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT);
    assertEq(usdc.balanceOf(VICTIM_ADDRESS), INCIDENT_AMOUNT);
    assertEq(usdc.balanceOf(HACKER_ADDRESS), 0);
  }

  function test_incident_victimCanWithdrawInParts() public {
    _runBatch(INCIDENT_BATCH, _one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));

    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, 1_000_000_000_000);
    assertEq(_pending(USDC, VICTIM_ADDRESS), INCIDENT_AMOUNT - 1_000_000_000_000);
    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT - 1_000_000_000_000);
    assertEq(_pending(USDC, VICTIM_ADDRESS), 0);
    assertEq(usdc.balanceOf(VICTIM_ADDRESS), INCIDENT_AMOUNT);

    vm.expectRevert(IZkLighter.ZkLighter_InvalidWithdrawAmount.selector);
    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, 1);
  }

  function test_incident_victimExistingPendingBalanceIsKept() public {
    zklighter.setPendingBalance(USDC, VICTIM_ACCOUNT, 777);
    _runBatch(INCIDENT_BATCH, _one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    assertEq(_pending(USDC, VICTIM_ADDRESS), uint128(INCIDENT_AMOUNT) + 777);
  }

  // ---------------------------------------------------------------------------------------------
  // Commitments are untouched
  // ---------------------------------------------------------------------------------------------

  function test_redirect_keepsOnChainOperationsHashOverOriginalAccount() public {
    WithdrawLog[] memory logs = _one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT));
    (bytes memory pubData, bytes32 hash) = _encode(logs);
    assertEq(hash, keccak256(abi.encodePacked(bytes32(0), TxTypes.OnChainPubDataType.Withdraw, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));

    Storage.StoredBatchInfo memory stored = _commitAndVerify(INCIDENT_BATCH, hash);
    _execute(stored, pubData);
    assertEq(_pending(USDC, VICTIM_ADDRESS), INCIDENT_AMOUNT);
  }

  function test_redirect_keepsLegacyOnChainOperationsHashOverOriginalAccount() public {
    (bytes memory pubData, bytes32 hash) = _encode(_one(_log(true, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    assertEq(hash, keccak256(abi.encodePacked(bytes32(0), TxTypes.OnChainPubDataType.USDCWithdraw, HACKER_ACCOUNT, INCIDENT_AMOUNT)));

    Storage.StoredBatchInfo memory stored = _commitAndVerify(INCIDENT_BATCH, hash);
    _execute(stored, pubData);
    assertEq(_pending(USDC, VICTIM_ADDRESS), INCIDENT_AMOUNT);
  }

  function test_redirect_pubDataRewrittenToVictimDoesNotMatchCommitment() public {
    (, bytes32 hash) = _encode(_one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    (bytes memory victimPubData, ) = _encode(_one(_log(false, VICTIM_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    Storage.StoredBatchInfo memory stored = _commitAndVerify(INCIDENT_BATCH, hash);

    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = stored;
    bytes[] memory pubDatas = new bytes[](1);
    pubDatas[0] = victimPubData;
    vm.expectRevert(IZkLighter.ZkLighter_OnChainOperationsHashMismatch.selector);
    zklighter.executeBatches(batches, pubDatas);
  }

  function test_redirect_pubDataWithDifferentAmountDoesNotMatchCommitment() public {
    (, bytes32 hash) = _encode(_one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    (bytes memory otherPubData, ) = _encode(_one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT + 1)));
    Storage.StoredBatchInfo memory stored = _commitAndVerify(INCIDENT_BATCH, hash);

    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = stored;
    bytes[] memory pubDatas = new bytes[](1);
    pubDatas[0] = otherPubData;
    vm.expectRevert(IZkLighter.ZkLighter_OnChainOperationsHashMismatch.selector);
    zklighter.executeBatches(batches, pubDatas);
  }

  // ---------------------------------------------------------------------------------------------
  // Batch number bound
  // ---------------------------------------------------------------------------------------------

  function test_redirect_appliesAtLastRedirectedBatch() public {
    _runBatch(LAST_REDIRECTED_BATCH, _one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    assertEq(_pending(USDC, HACKER_ADDRESS), 0);
    assertEq(_pending(USDC, VICTIM_ADDRESS), INCIDENT_AMOUNT);
  }

  function test_redirect_appliesAtLastRedirectedBatch_usdcWithdrawLog() public {
    _runBatch(LAST_REDIRECTED_BATCH, _one(_log(true, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    assertEq(_pending(USDC, HACKER_ADDRESS), 0);
    assertEq(_pending(USDC, VICTIM_ADDRESS), INCIDENT_AMOUNT);
  }

  function test_redirect_appliesAtLowBatchNumbers() public {
    _runBatch(2, _one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    assertEq(_pending(USDC, HACKER_ADDRESS), 0);
    assertEq(_pending(USDC, VICTIM_ADDRESS), INCIDENT_AMOUNT);
  }

  /// @dev Past the bound the redirect is off, but the blacklist still keeps the funds in the contract
  function _afterBoundStaysLocked(bool legacyUSDCType) internal {
    uint256 contractBefore = usdc.balanceOf(address(zklighter));
    _runBatch(LAST_REDIRECTED_BATCH + 1, _one(_log(legacyUSDCType, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));

    assertEq(_pending(USDC, HACKER_ADDRESS), INCIDENT_AMOUNT, "hacker is credited past the bound");
    assertEq(_pending(USDC, VICTIM_ADDRESS), 0, "victim is not credited past the bound");

    vm.prank(HACKER_ADDRESS);
    _expectBlacklistRevert();
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, USDC, INCIDENT_AMOUNT);

    assertEq(usdc.balanceOf(HACKER_ADDRESS), 0);
    assertEq(usdc.balanceOf(address(zklighter)), contractBefore, "funds stay in the contract");
    assertEq(_pending(USDC, HACKER_ADDRESS), INCIDENT_AMOUNT);
  }

  function test_redirect_doesNotApplyAfterBound_butBlacklistKeepsFundsInContract() public {
    _afterBoundStaysLocked(false);
  }

  function test_redirect_doesNotApplyAfterBound_butBlacklistKeepsFundsInContract_usdcWithdrawLog() public {
    _afterBoundStaysLocked(true);
  }

  function test_redirect_consecutiveBatchesAcrossTheBound() public {
    _runBatch(LAST_REDIRECTED_BATCH - 1, _one(_log(false, HACKER_ACCOUNT, USDC, 100)));
    _runBatch(LAST_REDIRECTED_BATCH, _one(_log(true, HACKER_ACCOUNT, USDC, 20)));
    _runBatch(LAST_REDIRECTED_BATCH + 1, _one(_log(false, HACKER_ACCOUNT, USDC, 3)));
    _runBatch(LAST_REDIRECTED_BATCH + 2, _one(_log(true, HACKER_ACCOUNT, USDC, 4)));

    assertEq(_pending(USDC, VICTIM_ADDRESS), 120);
    assertEq(_pending(USDC, HACKER_ADDRESS), 7);
  }

  function test_redirect_twoPendingBatchesExecutedInOneCall() public {
    (bytes memory pubData1, bytes32 hash1) = _encode(_one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    (bytes memory pubData2, bytes32 hash2) = _encode(_one(_log(false, OTHER_ACCOUNT, USDC, 55)));

    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](2);
    batches[0] = _commitAndVerify(INCIDENT_BATCH, hash1);
    batches[1] = _commitAndVerify(INCIDENT_BATCH + 1, hash2);
    assertEq(zklighter.pendingOnChainBatchesCount(), 2);
    assertEq(zklighter.executedBatchesCount(), INCIDENT_BATCH - 1, "nothing executes before executeBatches");

    bytes[] memory pubDatas = new bytes[](2);
    pubDatas[0] = pubData1;
    pubDatas[1] = pubData2;
    zklighter.executeBatches(batches, pubDatas);

    assertEq(_pending(USDC, VICTIM_ADDRESS), INCIDENT_AMOUNT);
    assertEq(_pending(USDC, HACKER_ADDRESS), 0);
    assertEq(_pending(USDC, OTHER_ADDRESS), 55);
    assertEq(zklighter.executedBatchesCount(), INCIDENT_BATCH + 1);
    assertEq(zklighter.pendingOnChainBatchesCount(), 0);
  }

  /// @dev The withdrawal sits behind earlier pending batches on mainnet; it cannot be executed out of order
  function test_redirect_incidentBatchCannotJumpTheExecutionQueue() public {
    (bytes memory pubData1, bytes32 hash1) = _encode(_one(_log(false, OTHER_ACCOUNT, USDC, 55)));
    (bytes memory pubData2, bytes32 hash2) = _encode(_one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    Storage.StoredBatchInfo memory first = _commitAndVerify(INCIDENT_BATCH - 1, hash1);
    Storage.StoredBatchInfo memory second = _commitAndVerify(INCIDENT_BATCH, hash2);

    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = second;
    bytes[] memory pubDatas = new bytes[](1);
    pubDatas[0] = pubData2;
    vm.expectRevert(IZkLighter.ZkLighter_BatchNotInOnChainQueue.selector);
    zklighter.executeBatches(batches, pubDatas);

    _execute(first, pubData1);
    _execute(second, pubData2);
    assertEq(_pending(USDC, VICTIM_ADDRESS), INCIDENT_AMOUNT);
    assertEq(_pending(USDC, OTHER_ADDRESS), 55);
  }

  function test_redirect_unverifiedIncidentBatchCannotBeExecuted() public {
    (bytes memory pubData, bytes32 hash) = _encode(_one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    Storage.StoredBatchInfo memory stored = _commitAndVerify(INCIDENT_BATCH, hash);
    // Roll verification back by one to model "committed, not yet verified"
    vm.store(
      address(zklighter),
      bytes32(uint256(9)),
      bytes32((uint256(vm.load(address(zklighter), bytes32(uint256(9)))) & ~uint256(type(uint64).max)) | (INCIDENT_BATCH - 1))
    );
    assertEq(zklighter.verifiedBatchesCount(), INCIDENT_BATCH - 1);

    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = stored;
    bytes[] memory pubDatas = new bytes[](1);
    pubDatas[0] = pubData;
    vm.expectRevert(IZkLighter.ZkLighter_CannotExecuteNonVerifiedBatch.selector);
    zklighter.executeBatches(batches, pubDatas);
  }

  // ---------------------------------------------------------------------------------------------
  // Scope of the redirect
  // ---------------------------------------------------------------------------------------------

  function test_redirect_nonUSDCAssetsFromHackerAreNotRedirected() public {
    WithdrawLog[] memory logs = new WithdrawLog[](2);
    logs[0] = _log(false, HACKER_ACCOUNT, ETH, 5_000);
    logs[1] = _log(false, HACKER_ACCOUNT, LIT, 7_000);
    _runBatch(INCIDENT_BATCH, logs);

    assertEq(_pending(ETH, VICTIM_ADDRESS), 0);
    assertEq(_pending(LIT, VICTIM_ADDRESS), 0);
    assertEq(_pending(USDC, VICTIM_ADDRESS), 0);
    assertEq(_pending(ETH, HACKER_ADDRESS), 5_000);
    assertEq(_pending(LIT, HACKER_ADDRESS), 7_000);

    uint256 ethBefore = address(zklighter).balance;
    uint256 litBefore = lit.balanceOf(address(zklighter));

    vm.prank(HACKER_ADDRESS);
    _expectBlacklistRevert();
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, ETH, 5_000);
    vm.prank(HACKER_ADDRESS);
    _expectBlacklistRevert();
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, LIT, 7_000);

    assertEq(address(zklighter).balance, ethBefore);
    assertEq(lit.balanceOf(address(zklighter)), litBefore);
    assertEq(HACKER_ADDRESS.balance, 0);
    assertEq(lit.balanceOf(HACKER_ADDRESS), 0);
  }

  function test_redirect_otherAccountsAreCreditedNormally() public {
    WithdrawLog[] memory logs = new WithdrawLog[](4);
    logs[0] = _log(false, OTHER_ACCOUNT, USDC, 1_250);
    logs[1] = _log(true, OTHER_ACCOUNT, USDC, 750);
    logs[2] = _log(false, OTHER_ACCOUNT, ETH, 300);
    logs[3] = _log(false, OTHER_ACCOUNT, LIT, 400);
    _runBatch(INCIDENT_BATCH, logs);

    assertEq(_pending(USDC, OTHER_ADDRESS), 2_000);
    assertEq(_pending(ETH, OTHER_ADDRESS), 300);
    assertEq(_pending(LIT, OTHER_ADDRESS), 400);
    assertEq(_pending(USDC, VICTIM_ADDRESS), 0);
    assertEq(_pending(USDC, HACKER_ADDRESS), 0);

    zklighter.withdrawPendingBalance(OTHER_ADDRESS, USDC, 2_000);
    zklighter.withdrawPendingBalance(OTHER_ADDRESS, ETH, 300);
    zklighter.withdrawPendingBalance(OTHER_ADDRESS, LIT, 400);
    assertEq(usdc.balanceOf(OTHER_ADDRESS), 2_000);
    assertEq(OTHER_ADDRESS.balance, 300 * ETH_TICK);
    assertEq(lit.balanceOf(OTHER_ADDRESS), 400 * LIT_TICK);
  }

  function test_redirect_neighbouringAccountIndexesAreNotRedirected() public {
    address below = address(0xB10);
    address above = address(0xAB0);
    zklighter.setAddressToAccountIndex(below, HACKER_ACCOUNT - 1);
    zklighter.setAddressToAccountIndex(above, HACKER_ACCOUNT + 1);

    WithdrawLog[] memory logs = new WithdrawLog[](4);
    logs[0] = _log(false, HACKER_ACCOUNT - 1, USDC, 11);
    logs[1] = _log(false, HACKER_ACCOUNT + 1, USDC, 22);
    logs[2] = _log(true, HACKER_ACCOUNT - 1, USDC, 33);
    logs[3] = _log(true, HACKER_ACCOUNT + 1, USDC, 44);
    _runBatch(INCIDENT_BATCH, logs);

    assertEq(_pending(USDC, below), 44);
    assertEq(_pending(USDC, above), 66);
    assertEq(_pending(USDC, VICTIM_ADDRESS), 0);
  }

  function test_redirect_victimOwnWithdrawalsStillWork() public {
    WithdrawLog[] memory logs = new WithdrawLog[](3);
    logs[0] = _log(false, VICTIM_ACCOUNT, USDC, 510_689_672);
    logs[1] = _log(false, VICTIM_ACCOUNT, LIT, 9);
    logs[2] = _log(false, VICTIM_ACCOUNT, ETH, 8);
    _runBatch(INCIDENT_BATCH, logs);

    assertEq(_pending(USDC, VICTIM_ADDRESS), 510_689_672);
    assertEq(_pending(LIT, VICTIM_ADDRESS), 9);
    assertEq(_pending(ETH, VICTIM_ADDRESS), 8);

    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, 510_689_672);
    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, LIT, 9);
    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, ETH, 8);
    assertEq(usdc.balanceOf(VICTIM_ADDRESS), 510_689_672);
    assertEq(lit.balanceOf(VICTIM_ADDRESS), 9 * LIT_TICK);
    assertEq(VICTIM_ADDRESS.balance, 8 * ETH_TICK);
  }

  function test_redirect_mixedBatchCreditsEveryAccountCorrectly() public {
    WithdrawLog[] memory logs = new WithdrawLog[](7);
    logs[0] = _log(false, OTHER_ACCOUNT, USDC, 1_000);
    logs[1] = _log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT);
    logs[2] = _log(false, VICTIM_ACCOUNT, USDC, 2_000);
    logs[3] = _log(true, HACKER_ACCOUNT, USDC, 50_000);
    logs[4] = _log(false, HACKER_ACCOUNT, ETH, 4_000);
    logs[5] = _log(true, OTHER_ACCOUNT, USDC, 5_000);
    logs[6] = _log(false, HACKER_ACCOUNT, USDC, 6_000);
    _runBatch(INCIDENT_BATCH, logs);

    assertEq(_pending(USDC, VICTIM_ADDRESS), uint128(INCIDENT_AMOUNT) + 2_000 + 50_000 + 6_000);
    assertEq(_pending(USDC, OTHER_ADDRESS), 6_000);
    assertEq(_pending(USDC, HACKER_ADDRESS), 0);
    assertEq(_pending(ETH, HACKER_ADDRESS), 4_000);
    assertEq(_pending(ETH, VICTIM_ADDRESS), 0);
  }

  function test_redirect_legacyPendingBalancesAreNotTouched() public {
    _runBatch(INCIDENT_BATCH, _one(_log(true, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    assertEq(zklighter.getPendingBalanceLegacy(VICTIM_ADDRESS), 0);
    assertEq(zklighter.getPendingBalanceLegacy(HACKER_ADDRESS), 0);
  }

  function test_redirect_maxAmountsAccumulateWithoutOverflow() public {
    WithdrawLog[] memory logs = new WithdrawLog[](3);
    logs[0] = _log(false, HACKER_ACCOUNT, USDC, type(uint64).max);
    logs[1] = _log(true, HACKER_ACCOUNT, USDC, type(uint64).max);
    logs[2] = _log(false, VICTIM_ACCOUNT, USDC, type(uint64).max);
    _runBatch(INCIDENT_BATCH, logs);
    assertEq(_pending(USDC, VICTIM_ADDRESS), uint128(type(uint64).max) * 3);
  }

  function test_redirect_zeroAmountWithdrawalIsHarmless() public {
    _runBatch(INCIDENT_BATCH, _one(_log(false, HACKER_ACCOUNT, USDC, 0)));
    assertEq(_pending(USDC, VICTIM_ADDRESS), 0);
    assertEq(_pending(USDC, HACKER_ADDRESS), 0);
  }

  // ---------------------------------------------------------------------------------------------
  // Fuzz
  // ---------------------------------------------------------------------------------------------

  function testFuzz_redirect_hackerUSDCWithinBoundAlwaysGoesToVictim(uint64 batchNumber, uint64 amount, bool legacyUSDCType) public {
    batchNumber = uint64(bound(batchNumber, 2, LAST_REDIRECTED_BATCH));
    _runBatch(batchNumber, _one(_log(legacyUSDCType, HACKER_ACCOUNT, USDC, amount)));
    assertEq(_pending(USDC, VICTIM_ADDRESS), amount);
    assertEq(_pending(USDC, HACKER_ADDRESS), 0);
  }

  function testFuzz_redirect_hackerUSDCPastBoundIsNeverPaidOut(uint64 batchNumber, uint64 amount, bool legacyUSDCType) public {
    batchNumber = uint64(bound(batchNumber, LAST_REDIRECTED_BATCH + 1, type(uint32).max));
    amount = uint64(bound(amount, 1, 1_000_000_000 * 10 ** 6));
    _runBatch(batchNumber, _one(_log(legacyUSDCType, HACKER_ACCOUNT, USDC, amount)));
    assertEq(_pending(USDC, VICTIM_ADDRESS), 0);
    assertEq(_pending(USDC, HACKER_ADDRESS), amount);

    _expectBlacklistRevert();
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, USDC, amount);
    assertEq(usdc.balanceOf(HACKER_ADDRESS), 0);
  }

  function testFuzz_redirect_hackerNonUSDCIsNeverRedirected(uint64 batchNumber, uint16 assetIndex, uint64 amount) public {
    batchNumber = uint64(bound(batchNumber, 2, type(uint32).max));
    vm.assume(assetIndex != USDC);
    _runBatch(batchNumber, _one(_log(false, HACKER_ACCOUNT, assetIndex, amount)));
    assertEq(_pending(assetIndex, VICTIM_ADDRESS), 0);
    assertEq(_pending(USDC, VICTIM_ADDRESS), 0);
    assertEq(_pending(assetIndex, HACKER_ADDRESS), amount);
  }

  function testFuzz_redirect_otherAccountsAreNeverRedirected(
    uint64 batchNumber,
    uint48 accountIndex,
    uint16 assetIndex,
    uint64 amount,
    bool legacyUSDCType
  ) public {
    batchNumber = uint64(bound(batchNumber, 2, type(uint32).max));
    vm.assume(accountIndex != HACKER_ACCOUNT && accountIndex != VICTIM_ACCOUNT && accountIndex != 0);
    if (legacyUSDCType) {
      assetIndex = USDC;
    }
    address owner = address(0xABCDEF);
    zklighter.setAddressToAccountIndex(owner, accountIndex);

    _runBatch(batchNumber, _one(_log(legacyUSDCType, accountIndex, assetIndex, amount)));
    assertEq(_pending(assetIndex, owner), amount);
    assertEq(_pending(assetIndex, VICTIM_ADDRESS), 0);
    assertEq(_pending(assetIndex, HACKER_ADDRESS), 0);
  }

  // ---------------------------------------------------------------------------------------------
  // Blacklist
  // ---------------------------------------------------------------------------------------------

  function test_blacklist_blocksEveryAssetForHackerAddress() public {
    zklighter.setPendingBalance(USDC, HACKER_ACCOUNT, INCIDENT_AMOUNT);
    zklighter.setPendingBalance(ETH, HACKER_ACCOUNT, 1_000);
    zklighter.setPendingBalance(LIT, HACKER_ACCOUNT, 1_000);

    uint16[3] memory assets = [USDC, ETH, LIT];
    for (uint256 i = 0; i < assets.length; ++i) {
      uint128 balance = _pending(assets[i], HACKER_ADDRESS);
      _expectBlacklistRevert();
      zklighter.withdrawPendingBalance(HACKER_ADDRESS, assets[i], balance);
      _expectBlacklistRevert();
      zklighter.withdrawPendingBalance(HACKER_ADDRESS, assets[i], 1);
      assertEq(_pending(assets[i], HACKER_ADDRESS), balance, "pending balance unchanged");
    }
    assertEq(usdc.balanceOf(HACKER_ADDRESS), 0);
    assertEq(lit.balanceOf(HACKER_ADDRESS), 0);
    assertEq(HACKER_ADDRESS.balance, 0);
  }

  function test_blacklist_doesNotDependOnCaller() public {
    zklighter.setPendingBalance(USDC, HACKER_ACCOUNT, INCIDENT_AMOUNT);
    address[4] memory callers = [HACKER_ADDRESS, VICTIM_ADDRESS, OTHER_ADDRESS, address(this)];
    for (uint256 i = 0; i < callers.length; ++i) {
      vm.prank(callers[i]);
      _expectBlacklistRevert();
      zklighter.withdrawPendingBalance(HACKER_ADDRESS, USDC, INCIDENT_AMOUNT);
    }
    assertEq(usdc.balanceOf(HACKER_ADDRESS), 0);
  }

  function test_blacklist_blocksLegacyWithdrawPath() public {
    zklighter.setDeprecatedPendingBalance(HACKER_ACCOUNT, INCIDENT_AMOUNT);
    _expectBlacklistRevert();
    zklighter.withdrawPendingBalanceLegacy(HACKER_ADDRESS, INCIDENT_AMOUNT);
    assertEq(zklighter.getPendingBalanceLegacy(HACKER_ADDRESS), INCIDENT_AMOUNT);
    assertEq(usdc.balanceOf(HACKER_ADDRESS), 0);
  }

  function test_blacklist_legacyWithdrawPathStillWorksForOthers() public {
    zklighter.setDeprecatedPendingBalance(VICTIM_ACCOUNT, 1_250);
    zklighter.withdrawPendingBalanceLegacy(VICTIM_ADDRESS, 1_250);
    assertEq(usdc.balanceOf(VICTIM_ADDRESS), 1_250);
  }

  function test_blacklist_holdsInDesertMode() public {
    zklighter.setPendingBalance(USDC, HACKER_ACCOUNT, INCIDENT_AMOUNT);
    zklighter.setPendingBalance(ETH, HACKER_ACCOUNT, 1_000);
    zklighter.setDeprecatedPendingBalance(HACKER_ACCOUNT, 99);
    zklighter.setDesertMode(true);

    _expectBlacklistRevert();
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, USDC, INCIDENT_AMOUNT);
    _expectBlacklistRevert();
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, ETH, 1_000);
    _expectBlacklistRevert();
    zklighter.withdrawPendingBalanceLegacy(HACKER_ADDRESS, 99);
    assertEq(usdc.balanceOf(HACKER_ADDRESS), 0);
    assertEq(HACKER_ADDRESS.balance, 0);
  }

  function test_blacklist_holdsWhilePausedAndInDesertMode() public {
    address pauseGuardian = address(0x9A1);
    governance.overrideGuardians(pauseGuardian, address(0x9A2));
    zklighter.setPendingBalance(USDC, HACKER_ACCOUNT, INCIDENT_AMOUNT);
    zklighter.setPendingBalance(USDC, VICTIM_ACCOUNT, INCIDENT_AMOUNT);

    vm.prank(pauseGuardian);
    governance.pauseSystem(2 hours);
    vm.expectRevert(EmergencyPause.Paused.selector);
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, USDC, INCIDENT_AMOUNT);

    zklighter.setDesertMode(true);
    _expectBlacklistRevert();
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, USDC, INCIDENT_AMOUNT);

    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT);
    assertEq(usdc.balanceOf(VICTIM_ADDRESS), INCIDENT_AMOUNT);
    assertEq(usdc.balanceOf(HACKER_ADDRESS), 0);
  }

  function test_blacklist_desertExitForHackerIsCreditedButNeverPaid() public {
    zklighter.setDesertMode(true);
    uint128 amount = 50_000;
    zklighter.performDesert(HACKER_ACCOUNT, HACKER_ADDRESS, USDC, amount, hex"AAAA");
    assertEq(_pending(USDC, HACKER_ADDRESS), amount);
    assertEq(_pending(USDC, VICTIM_ADDRESS), 0, "desert exits are not redirected");

    _expectBlacklistRevert();
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, USDC, amount);
    assertEq(usdc.balanceOf(HACKER_ADDRESS), 0);
  }

  function test_blacklist_desertExitForVictimIsPaid() public {
    zklighter.setDesertMode(true);
    zklighter.performDesert(VICTIM_ACCOUNT, VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT, hex"AAAA");
    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT);
    assertEq(usdc.balanceOf(VICTIM_ADDRESS), INCIDENT_AMOUNT);
  }

  function test_blacklist_redirectedFundsStayWithdrawableInDesertMode() public {
    _runBatch(INCIDENT_BATCH, _one(_log(false, HACKER_ACCOUNT, USDC, INCIDENT_AMOUNT)));
    zklighter.setDesertMode(true);
    zklighter.withdrawPendingBalance(VICTIM_ADDRESS, USDC, INCIDENT_AMOUNT);
    assertEq(usdc.balanceOf(VICTIM_ADDRESS), INCIDENT_AMOUNT);
  }

  function test_blacklist_transferFunctionsRejectDirectCalls() public {
    _expectBlacklistRevert();
    zklighter.transferERC20(usdc, HACKER_ADDRESS, 1, 1);
    _expectBlacklistRevert();
    zklighter.transferETH(HACKER_ADDRESS, 1);

    vm.expectRevert(IZkLighter.ZkLighter_OnlyZkLighter.selector);
    zklighter.transferERC20(usdc, VICTIM_ADDRESS, 1, 1);
    vm.expectRevert(IZkLighter.ZkLighter_OnlyZkLighter.selector);
    zklighter.transferETH(VICTIM_ADDRESS, 1);
  }

  /// @dev The blacklist is on the recipient. The hacker address acting as a caller for someone else
  /// only moves that owner's funds to that owner
  function test_blacklist_hackerAsCallerCannotDivertOtherOwnersFunds() public {
    zklighter.setPendingBalance(USDC, OTHER_ACCOUNT, 1_250);
    vm.prank(HACKER_ADDRESS);
    zklighter.withdrawPendingBalance(OTHER_ADDRESS, USDC, 1_250);
    assertEq(usdc.balanceOf(OTHER_ADDRESS), 1_250);
    assertEq(usdc.balanceOf(HACKER_ADDRESS), 0);
  }

  function testFuzz_blacklist_otherRecipientsCanWithdrawUSDC(address owner, uint48 accountIndex, uint64 amount) public {
    vm.assume(owner != HACKER_ADDRESS && owner != address(0) && owner != address(zklighter));
    vm.assume(accountIndex != 0 && accountIndex != HACKER_ACCOUNT);
    amount = uint64(bound(amount, 1, 1_000_000_000 * 10 ** 6));
    zklighter.setAddressToAccountIndex(owner, accountIndex);
    zklighter.setPendingBalance(USDC, accountIndex, amount);

    uint256 before = usdc.balanceOf(owner);
    zklighter.withdrawPendingBalance(owner, USDC, amount);
    assertEq(usdc.balanceOf(owner), before + amount);
    assertEq(_pending(USDC, owner), 0);
  }

  function testFuzz_blacklist_hackerNeverReceivesAnyAsset(uint8 assetSeed, uint64 balance, uint64 amount, address caller) public {
    uint16[3] memory assets = [USDC, ETH, LIT];
    uint16 assetIndex = assets[assetSeed % 3];
    balance = uint64(bound(balance, 1, 10 ** 12));
    amount = uint64(bound(amount, 1, balance));
    zklighter.setPendingBalance(assetIndex, HACKER_ACCOUNT, balance);

    vm.prank(caller);
    _expectBlacklistRevert();
    zklighter.withdrawPendingBalance(HACKER_ADDRESS, assetIndex, amount);
    assertEq(_pending(assetIndex, HACKER_ADDRESS), balance);
  }
}
