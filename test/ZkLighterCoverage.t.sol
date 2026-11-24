// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";

import {ZkLighterTest} from "../contracts/test/ZkLighterTest.sol";
import {AdditionalZkLighter} from "../contracts/AdditionalZkLighter.sol";
import {IZkLighter, IZkLighterPublic} from "../contracts/interfaces/IZkLighter.sol";
import {Storage} from "../contracts/Storage.sol";
import {ExtendableStorage} from "../contracts/ExtendableStorage.sol";
import {Config} from "../contracts/Config.sol";
import {OwnableERC20} from "../contracts/test/OwnableERC20.sol";
import {GovernanceTest} from "../contracts/test/GovernanceTest.sol";
import {IGovernance} from "../contracts/interfaces/IGovernance.sol";
import {IEvents} from "../contracts/interfaces/IEvents.sol";
import {ZkLighterVerifierTest} from "../contracts/test/ZkLighterVerifierTest.sol";
import {IZkLighterStateRootUpgradeVerifier} from "../contracts/interfaces/IZkLighterStateRootUpgradeVerifier.sol";
import {TxTypes} from "../contracts/lib/TxTypes.sol";
import {L1CoreMessaging} from "../contracts/messaging/L1CoreMessaging.sol";
import {Proxy} from "../contracts/proxy/Proxy.sol";
import {ExcessTransferToken, FeeOnTransferToken} from "./helpers/TestTokens.sol";

contract StateRootUpgradeVerifierMock is IZkLighterStateRootUpgradeVerifier {
  bool public accept = true;
  bool public checkInput;
  uint256 public expectedInput;

  function setAccept(bool _accept) external {
    accept = _accept;
  }

  function setExpectedInput(uint256 _expected) external {
    checkInput = true;
    expectedInput = _expected;
  }

  function Verify(bytes calldata, uint256[] calldata inputs) external view returns (bool) {
    return accept && (!checkInput || (inputs.length == 1 && inputs[0] == expectedInput));
  }
}

/// Coverage for paths flagged by the Zellic audit (finding 3.4): updateStateRoot, revertBatches,
/// legacy pending balances, asset config validation, non-standard ERC20 deposits and priority
/// request counter invariants exercised through the real entrypoints.
contract ZkLighterCoverageTests is Test, Config {
  OwnableERC20 usdc;
  OwnableERC20 lit;
  ZkLighterTest zklighter;
  GovernanceTest governance;
  L1CoreMessaging coreMessaging;
  address testAddress = address(0x1234);
  uint48 testAccountIndex = 1234;
  address treasuryAddress = makeAddr("treasury");
  address other = makeAddr("other");

  bytes pubData;
  bytes32 constant BLOB_HASH = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
  Storage.StoredBatchInfo batch1;

  function setUp() public {
    zklighter = new ZkLighterTest();
    governance = new GovernanceTest();
    usdc = new OwnableERC20("USD Coin", "USDC", 6);
    lit = new OwnableERC20("Lighter", "LIT", 18);
    zklighter.setAdditionalZkLighterAddress(address(new AdditionalZkLighter()));

    governance.overrideUSDCAddress(usdc);
    governance.overrideValidator(address(this), true);
    governance.overrideNetworkGovernor(address(this));
    zklighter.setGovernanceAddress(address(governance));
    zklighter.setVerifierAddress(address(new ZkLighterVerifierTest()));

    pubData = hex"0071d46f9b04e49c1c89863e820571ec1fef14467de4c91087d67518e8a3f42c203c6250bad14238cb26c02973200ef5cfed332e01508064fe36cfc021d5503525b8900a6dd9bd485d615b1cc6a6dbb1bafc886aa27338b981c9edb33d77b66edbf698abe5e7e75de6bb0bf53dba2ce36990e8d5db1a9a08078fcc8f9315b20f427ce82135502c725c89380ddf685d7f00890d5d24824b818b0bb790ec49f9c12c";

    batch1 = Storage.StoredBatchInfo({
      batchNumber: 1,
      endBlockNumber: 1,
      batchSize: 1,
      startTimestamp: 2,
      endTimestamp: 3,
      priorityRequestCount: 0,
      prefixPriorityRequestHash: bytes32(0),
      onChainOperationsHash: bytes32(0),
      stateRoot: keccak256(abi.encode("stateRoot")),
      validiumRoot: keccak256(abi.encode("validiumRoot")),
      commitment: bytes32(0)
    });
    zklighter.setStoredBatchHash(1, keccak256(abi.encode(batch1)));
    zklighter.setCommittedBatchesCount(1);

    zklighter.setAddressToAccountIndex(testAddress, testAccountIndex);
    zklighter.setLastAccountIndex(testAccountIndex);
    vm.deal(testAddress, 100 ether);
    usdc.mint(testAddress, 1_000_000_000 * 10 ** 6);
    usdc.mint(address(zklighter), 1_000_000_000 * 10 ** 6);
    lit.mint(testAddress, 1_000_000 * 10 ** 18);

    zklighter.registerDefaultAssetConfigs();
    zklighter.registerAssetConfig(2, address(lit), 0, 10 ** 6, 10 ** 12, (2 ** 50) - 1, 100);

    L1CoreMessaging impl = new L1CoreMessaging();
    coreMessaging = L1CoreMessaging(address(new Proxy(address(impl), abi.encode(address(zklighter), address(governance)))));
    zklighter.setCoreMessaging(address(coreMessaging));
  }

  /*//////////////////////////////////////////////////////////////
                              HELPERS
  //////////////////////////////////////////////////////////////*/

  function _readBytes32(bytes memory data, uint256 offset) internal pure returns (bytes32 out) {
    assembly {
      out := mload(add(add(data, 0x20), offset))
    }
  }

  /// @dev Mirrors ZkLighter.commitBatch's commitment derivation so tests can rebuild the exact StoredBatchInfo.
  function _expectedCommitment(IZkLighter.CommitBatchInfo memory c, bytes32 oldStateRoot) internal view returns (bytes32) {
    bytes32 blobCommitment = keccak256(abi.encodePacked(_readBytes32(pubData, 1), _readBytes32(pubData, 33), BLOB_HASH));
    return
      keccak256(
        abi.encodePacked(
          c.endBlockNumber,
          c.batchSize,
          c.startTimestamp,
          c.endTimestamp,
          oldStateRoot,
          c.newStateRoot,
          c.newValidiumRoot,
          c.onChainOperationsHash,
          c.priorityRequestCount,
          c.prefixPriorityRequestHash,
          blobCommitment
        )
      );
  }

  function _nextCommit(Storage.StoredBatchInfo memory last) internal view returns (IZkLighter.CommitBatchInfo memory c) {
    c = IZkLighter.CommitBatchInfo({
      endBlockNumber: last.endBlockNumber + 1,
      batchSize: 1,
      startTimestamp: last.endTimestamp,
      endTimestamp: last.endTimestamp + 2,
      priorityRequestCount: 0,
      prefixPriorityRequestHash: bytes32(0),
      onChainOperationsHash: bytes32(0),
      newStateRoot: keccak256(abi.encode("stateRoot", last.batchNumber + 1)),
      newValidiumRoot: keccak256(abi.encode("validiumRoot", last.batchNumber + 1)),
      pubdataCommitments: pubData
    });
  }

  /// @dev Commits `c` through the real entrypoint and returns the StoredBatchInfo the contract stored for it.
  function _commit(
    IZkLighter.CommitBatchInfo memory c,
    Storage.StoredBatchInfo memory last
  ) internal returns (Storage.StoredBatchInfo memory stored) {
    uint64 batchNumber = zklighter.committedBatchesCount() + 1;
    bytes32 oldStateRoot = zklighter.stateRootUpdates(batchNumber - 1);
    if (oldStateRoot == bytes32(0)) oldStateRoot = last.stateRoot;

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = BLOB_HASH;
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(c, last);

    stored = Storage.StoredBatchInfo({
      batchNumber: batchNumber,
      endBlockNumber: c.endBlockNumber,
      batchSize: c.batchSize,
      startTimestamp: c.startTimestamp,
      endTimestamp: c.endTimestamp,
      priorityRequestCount: c.priorityRequestCount,
      prefixPriorityRequestHash: c.prefixPriorityRequestHash,
      onChainOperationsHash: c.onChainOperationsHash,
      stateRoot: c.newStateRoot,
      validiumRoot: c.newValidiumRoot,
      commitment: _expectedCommitment(c, oldStateRoot)
    });
    assertEq(zklighter.storedBatchHashes(batchNumber), keccak256(abi.encode(stored)), "reconstructed StoredBatchInfo must match on-chain hash");
  }

  function _withdrawLog(uint48 masterAccountIndex, uint16 assetIndex, uint64 baseAmount) internal pure returns (bytes memory log, bytes32 hash) {
    log = abi.encodePacked(TxTypes.OnChainPubDataType.Withdraw, masterAccountIndex, assetIndex, baseAmount);
    hash = keccak256(abi.encodePacked(bytes32(0), TxTypes.OnChainPubDataType.Withdraw, masterAccountIndex, assetIndex, baseAmount));
  }

  function _depositUsdc(address to, uint256 amount) internal {
    vm.startPrank(testAddress);
    usdc.approve(address(zklighter), amount);
    zklighter.depositTest(to, USDC_ASSET_INDEX, TxTypes.RouteType.Perps, amount);
    vm.stopPrank();
  }

  function _paddedPrefix(bytes32 prev, bytes memory request) internal pure returns (bytes32) {
    bytes memory padded = new bytes(MAX_PRIORITY_REQUEST_PUBDATA_SIZE);
    for (uint256 i = 0; i < request.length; ++i) padded[i] = request[i];
    return keccak256(abi.encodePacked(prev, padded));
  }

  function _assertCounterInvariants(string memory step) internal view {
    uint64 executed = zklighter.executedPriorityRequestCount();
    uint64 verified = zklighter.verifiedPriorityRequestCount();
    uint64 committed = zklighter.committedPriorityRequestCount();
    uint64 open = zklighter.openPriorityRequestCount();
    assertLe(executed, verified, string.concat(step, ": executed <= verified"));
    assertLe(verified, committed, string.concat(step, ": verified <= committed"));
    assertLe(committed, executed + open, string.concat(step, ": committed <= executed + open"));
    assertLe(zklighter.executedBatchesCount(), zklighter.verifiedBatchesCount(), string.concat(step, ": executedBatches <= verifiedBatches"));
    assertLe(zklighter.verifiedBatchesCount(), zklighter.committedBatchesCount(), string.concat(step, ": verifiedBatches <= committedBatches"));
    assertLe(
      zklighter.executedOnChainBatchesCount() + zklighter.pendingOnChainBatchesCount(),
      zklighter.committedBatchesCount(),
      string.concat(step, ": on-chain queue <= committed")
    );
  }

  /*//////////////////////////////////////////////////////////////
                           updateStateRoot
  //////////////////////////////////////////////////////////////*/

  function _newRoots() internal pure returns (bytes32, bytes32) {
    return (keccak256("upgradedStateRoot"), keccak256("upgradedValidiumRoot"));
  }

  function test_updateStateRoot_revertsWhenVerifierNotSet() public {
    zklighter.verifyBatch(batch1, hex"AAAA"); // executed == committed == 1
    (bytes32 s, bytes32 v) = _newRoots();
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.updateStateRootTest(batch1, s, v, hex"");
  }

  function test_updateStateRoot_revertsOnStoredBatchMismatch() public {
    zklighter.verifyBatch(batch1, hex"AAAA");
    zklighter.setStateRootUpgradeVerifierAddress(address(new StateRootUpgradeVerifierMock()));
    Storage.StoredBatchInfo memory wrong = batch1;
    wrong.stateRoot = keccak256("tampered");
    (bytes32 s, bytes32 v) = _newRoots();
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.updateStateRootTest(wrong, s, v, hex"");
  }

  function test_updateStateRoot_revertsWhenCommittedNotExecuted() public {
    // setUp: committed == 1, executed == 0
    zklighter.setStateRootUpgradeVerifierAddress(address(new StateRootUpgradeVerifierMock()));
    (bytes32 s, bytes32 v) = _newRoots();
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.updateStateRootTest(batch1, s, v, hex"");
  }

  function test_updateStateRoot_revertsOnInvalidProof() public {
    zklighter.verifyBatch(batch1, hex"AAAA");
    StateRootUpgradeVerifierMock verifier = new StateRootUpgradeVerifierMock();
    verifier.setAccept(false);
    zklighter.setStateRootUpgradeVerifierAddress(address(verifier));
    (bytes32 s, bytes32 v) = _newRoots();
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.updateStateRootTest(batch1, s, v, hex"");
  }

  function test_updateStateRoot_revertsForNonValidator() public {
    zklighter.verifyBatch(batch1, hex"AAAA");
    zklighter.setStateRootUpgradeVerifierAddress(address(new StateRootUpgradeVerifierMock()));
    (bytes32 s, bytes32 v) = _newRoots();
    vm.prank(other);
    vm.expectRevert(IGovernance.ZkLighter_Governance_InvalidValidator.selector);
    zklighter.updateStateRootTest(batch1, s, v, hex"");
  }

  function test_updateStateRoot_successUpdatesRootsDisablesVerifierAndFeedsNextCommit() public {
    zklighter.verifyBatch(batch1, hex"AAAA");
    (bytes32 s, bytes32 v) = _newRoots();

    StateRootUpgradeVerifierMock verifier = new StateRootUpgradeVerifierMock();
    verifier.setExpectedInput(uint256(keccak256(abi.encodePacked(zklighter.stateRoot(), zklighter.validiumRoot(), s, v))) % BN254_MODULUS);
    zklighter.setStateRootUpgradeVerifierAddress(address(verifier));

    vm.expectEmit();
    emit IEvents.StateRootUpdate(1, batch1.stateRoot, s);
    zklighter.updateStateRootTest(batch1, s, v, hex"");

    assertEq(zklighter.stateRoot(), s);
    assertEq(zklighter.validiumRoot(), v);
    assertEq(zklighter.lastVerifiedStateRoot(), s);
    assertEq(zklighter.lastVerifiedValidiumRoot(), v);
    assertEq(zklighter.stateRootUpdates(1), s);

    // Verifier is single-use: a second update is rejected.
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.updateStateRootTest(batch1, s, v, hex"");

    // The next commit must chain from the upgraded root, not from lastStoredBatch.stateRoot.
    IZkLighter.CommitBatchInfo memory c = _nextCommit(batch1);
    Storage.StoredBatchInfo memory batch2 = _commit(c, batch1);
    assertEq(batch2.commitment, _expectedCommitment(c, s));
    assertTrue(batch2.commitment != _expectedCommitment(c, batch1.stateRoot));
  }

  /*//////////////////////////////////////////////////////////////
                            revertBatches
  //////////////////////////////////////////////////////////////*/

  function _single(Storage.StoredBatchInfo memory b) internal pure returns (Storage.StoredBatchInfo[] memory arr) {
    arr = new Storage.StoredBatchInfo[](1);
    arr[0] = b;
  }

  function test_revertBatches_revertsForNonValidator() public {
    Storage.StoredBatchInfo memory batch2 = _commit(_nextCommit(batch1), batch1);
    vm.prank(other);
    vm.expectRevert(IGovernance.ZkLighter_Governance_InvalidValidator.selector);
    zklighter.revertBatches(_single(batch2), batch1);
  }

  function test_revertBatches_revertsOnGenesisBatch() public {
    Storage.StoredBatchInfo memory genesis;
    vm.expectRevert(IZkLighter.ZkLighter_CannotRevertGenesisBatch.selector);
    zklighter.revertBatches(_single(genesis), batch1);
  }

  function test_revertBatches_revertsOnStoredBatchMismatch() public {
    Storage.StoredBatchInfo memory batch2 = _commit(_nextCommit(batch1), batch1);
    Storage.StoredBatchInfo memory tampered = batch2;
    tampered.stateRoot = keccak256("tampered");
    vm.expectRevert(IZkLighter.ZkLighter_StoredBatchInfoMismatch.selector);
    zklighter.revertBatches(_single(tampered), batch1);
  }

  function test_revertBatches_revertsOnRemainingBatchMismatch() public {
    Storage.StoredBatchInfo memory batch2 = _commit(_nextCommit(batch1), batch1);
    Storage.StoredBatchInfo memory wrongRemaining = batch1;
    wrongRemaining.endTimestamp = 99;
    vm.expectRevert(IZkLighter.ZkLighter_StoredBatchInfoMismatch.selector);
    zklighter.revertBatches(_single(batch2), wrongRemaining);
  }

  function test_revertBatches_cannotRevertExecutedBatch() public {
    zklighter.verifyBatch(batch1, hex"AAAA"); // batch 1 lazily executed
    vm.expectRevert(IZkLighter.ZkLighter_CannotRevertExecutedBatch.selector);
    zklighter.revertBatches(_single(batch1), batch1);
  }

  function test_revertBatches_committedOnlyBatch() public {
    zklighter.verifyBatch(batch1, hex"AAAA");
    Storage.StoredBatchInfo memory batch2 = _commit(_nextCommit(batch1), batch1);
    assertEq(zklighter.committedBatchesCount(), 2);

    vm.expectEmit();
    emit IEvents.BatchesRevert(1);
    zklighter.revertBatches(_single(batch2), batch1);

    assertEq(zklighter.committedBatchesCount(), 1);
    assertEq(zklighter.verifiedBatchesCount(), 1);
    assertEq(zklighter.executedBatchesCount(), 1);
    assertEq(zklighter.storedBatchHashes(2), bytes32(0), "reverted batch hash cleared");
    assertEq(zklighter.storedBatchHashes(1), keccak256(abi.encode(batch1)), "remaining batch untouched");
    _assertCounterInvariants("after revert");

    // Batch 2 can be re-committed with different content.
    IZkLighter.CommitBatchInfo memory c = _nextCommit(batch1);
    c.newStateRoot = keccak256("replacement");
    Storage.StoredBatchInfo memory replacement = _commit(c, batch1);
    assertEq(zklighter.committedBatchesCount(), 2);
    assertTrue(replacement.commitment != batch2.commitment);
  }

  function test_revertBatches_verifiedPendingOnChainBatchRollsBackCountersAndQueue() public {
    zklighter.verifyBatch(batch1, hex"AAAA");
    uint64 usdcAmount = 1_000_000;
    _depositUsdc(testAddress, usdcAmount);

    IZkLighter.CommitBatchInfo memory c = _nextCommit(batch1);
    c.priorityRequestCount = 1;
    c.prefixPriorityRequestHash = zklighter.getPriorityRequest(0).prefixHash;
    (, c.onChainOperationsHash) = _withdrawLog(testAccountIndex, USDC_ASSET_INDEX, usdcAmount);
    Storage.StoredBatchInfo memory batch2 = _commit(c, batch1);
    zklighter.verifyBatch(batch2, hex"AAAA");

    assertEq(zklighter.verifiedBatchesCount(), 2);
    assertEq(zklighter.executedBatchesCount(), 1, "on-chain ops keep batch 2 pending");
    assertEq(zklighter.pendingOnChainBatchesCount(), 1);
    assertEq(zklighter.committedPriorityRequestCount(), 1);
    assertEq(zklighter.verifiedPriorityRequestCount(), 1);
    assertEq(zklighter.lastVerifiedStateRoot(), batch2.stateRoot);

    zklighter.revertBatches(_single(batch2), batch1);

    assertEq(zklighter.committedBatchesCount(), 1);
    assertEq(zklighter.verifiedBatchesCount(), 1);
    assertEq(zklighter.executedBatchesCount(), 1);
    assertEq(zklighter.pendingOnChainBatchesCount(), 0);
    assertEq(zklighter.getOnChainExecution(0).batchNumber, 0, "queue entry cleared");
    assertEq(zklighter.committedPriorityRequestCount(), 0);
    assertEq(zklighter.verifiedPriorityRequestCount(), 0);
    assertEq(zklighter.executedPriorityRequestCount(), 0);
    assertEq(zklighter.openPriorityRequestCount(), 1, "deposit stays queued");
    assertEq(zklighter.lastVerifiedStateRoot(), batch1.stateRoot, "lastVerified roots restored from remaining batch");
    assertEq(zklighter.lastVerifiedValidiumRoot(), batch1.validiumRoot);
    assertEq(zklighter.lastVerifiedEndBlockNumber(), batch1.endBlockNumber);
    _assertCounterInvariants("after revert");
  }

  function test_revertBatches_multipleBatchesNewestFirst() public {
    zklighter.verifyBatch(batch1, hex"AAAA");
    Storage.StoredBatchInfo memory batch2 = _commit(_nextCommit(batch1), batch1);
    Storage.StoredBatchInfo memory batch3 = _commit(_nextCommit(batch2), batch2);
    assertEq(zklighter.committedBatchesCount(), 3);

    Storage.StoredBatchInfo[] memory toRevert = new Storage.StoredBatchInfo[](2);
    toRevert[0] = batch3;
    toRevert[1] = batch2;
    zklighter.revertBatches(toRevert, batch1);

    assertEq(zklighter.committedBatchesCount(), 1);
    assertEq(zklighter.storedBatchHashes(2), bytes32(0));
    assertEq(zklighter.storedBatchHashes(3), bytes32(0));

    // Oldest-first ordering is rejected since the hash at committedBatchesCount is the newest.
    batch2 = _commit(_nextCommit(batch1), batch1);
    batch3 = _commit(_nextCommit(batch2), batch2);
    toRevert[0] = batch2;
    toRevert[1] = batch3;
    vm.expectRevert(IZkLighter.ZkLighter_StoredBatchInfoMismatch.selector);
    zklighter.revertBatches(toRevert, batch1);
  }

  /*//////////////////////////////////////////////////////////////
                      legacy pending balances
  //////////////////////////////////////////////////////////////*/

  function test_legacyPendingBalance_getterAndWithdraw() public {
    zklighter.setDeprecatedPendingBalance(testAccountIndex, 500);
    assertEq(zklighter.getPendingBalanceLegacy(testAddress), 500);
    assertEq(zklighter.getPendingBalanceLegacy(other), 0, "unregistered address resolves to NIL and has no legacy balance");

    vm.expectRevert(IZkLighter.ZkLighter_InvalidWithdrawAmount.selector);
    zklighter.withdrawPendingBalanceLegacy(testAddress, 0);
    vm.expectRevert(IZkLighter.ZkLighter_InvalidWithdrawAmount.selector);
    zklighter.withdrawPendingBalanceLegacy(testAddress, 501);
    vm.expectRevert(IZkLighter.ZkLighter_InvalidWithdrawAmount.selector);
    zklighter.withdrawPendingBalanceLegacy(other, 1);

    uint256 before = usdc.balanceOf(testAddress);
    vm.prank(other); // anyone may trigger the payout, funds always go to the owner
    vm.expectEmit();
    emit IEvents.WithdrawPending(testAddress, USDC_ASSET_INDEX, 200);
    zklighter.withdrawPendingBalanceLegacy(testAddress, 200);

    assertEq(usdc.balanceOf(testAddress), before + 200);
    assertEq(zklighter.getPendingBalanceLegacy(testAddress), 300);

    zklighter.withdrawPendingBalanceLegacy(testAddress, 300);
    assertEq(zklighter.getPendingBalanceLegacy(testAddress), 0);
    assertEq(usdc.balanceOf(testAddress), before + 500);
  }

  /*//////////////////////////////////////////////////////////////
                  registerAssetConfig / updateAssetConfig
  //////////////////////////////////////////////////////////////*/

  uint16 constant NEW_ASSET = 4;

  function _register(uint16 assetIndex, address token, uint8 withdrawals, uint56 extMul, uint128 tick, uint64 cap, uint64 minDep) internal {
    zklighter.registerAssetConfig(assetIndex, token, withdrawals, extMul, tick, cap, minDep);
  }

  function _expectRegisterRevert(
    bytes4 selector,
    uint16 assetIndex,
    address token,
    uint8 withdrawals,
    uint56 extMul,
    uint128 tick,
    uint64 cap,
    uint64 minDep
  ) internal {
    vm.expectRevert(selector);
    _register(assetIndex, token, withdrawals, extMul, tick, cap, minDep);
  }

  function test_registerAssetConfig_success() public {
    OwnableERC20 token = new OwnableERC20("New", "NEW", 18);
    vm.expectEmit();
    emit IEvents.RegisterAssetConfig(NEW_ASSET, address(token), 1, 1000, 10 ** 12, 10 ** 9, 5);
    _register(NEW_ASSET, address(token), 1, 1000, 10 ** 12, 10 ** 9, 5);

    ExtendableStorage.AssetConfig memory cfg = zklighter.getAssetConfig(NEW_ASSET);
    assertEq(cfg.tokenAddress, address(token));
    assertEq(cfg.withdrawalsEnabled, 1);
    assertEq(cfg.extensionMultiplier, 1000);
    assertEq(cfg.tickSize, 10 ** 12);
    assertEq(cfg.depositCapTicks, 10 ** 9);
    assertEq(cfg.minDepositTicks, 5);
    assertEq(zklighter.tokenToAssetIndex(address(token)), NEW_ASSET);
  }

  function test_registerAssetConfig_revertsForNonGovernor() public {
    OwnableERC20 token = new OwnableERC20("New", "NEW", 18);
    vm.prank(other);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    _register(NEW_ASSET, address(token), 1, 1000, 10 ** 12, 10 ** 9, 5);
  }

  function test_registerAssetConfig_revertsOnInvalidAssetIndex() public {
    address token = address(new OwnableERC20("New", "NEW", 18));
    bytes4 sel = IZkLighter.ZkLighter_InvalidAssetIndex.selector;
    _expectRegisterRevert(sel, NATIVE_ASSET_INDEX, token, 1, 1000, 1, 100, 1); // native slot is reserved
    _expectRegisterRevert(sel, USDC_ASSET_INDEX, token, 1, 1000, 1, 100, 1); // already registered
    _expectRegisterRevert(sel, 2, token, 1, 1000, 1, 100, 1); // already registered (LIT)
    _expectRegisterRevert(sel, 0, token, 1, 1000, 1, 100, 1); // < MIN_ASSET_INDEX
    _expectRegisterRevert(sel, MAX_ASSET_INDEX + 1, token, 1, 1000, 1, 100, 1);
  }

  function test_registerAssetConfig_revertsOnInvalidToken() public {
    bytes4 sel = IZkLighter.ZkLighter_InvalidAssetConfigParams.selector;
    _expectRegisterRevert(sel, NEW_ASSET, address(0), 1, 1000, 1, 100, 1);
    _expectRegisterRevert(sel, NEW_ASSET, address(usdc), 1, 1000, 1, 100, 1); // token already mapped to asset 3
    _expectRegisterRevert(sel, NEW_ASSET, makeAddr("eoa"), 1, 1000, 1, 100, 1); // no code
  }

  function test_registerAssetConfig_revertsOnInvalidParams() public {
    address token = address(new OwnableERC20("New", "NEW", 18));
    bytes4 sel = IZkLighter.ZkLighter_InvalidAssetConfigParams.selector;
    _expectRegisterRevert(sel, NEW_ASSET, token, 2, 1000, 1, 100, 1); // withdrawalsEnabled not boolean
    _expectRegisterRevert(sel, NEW_ASSET, token, 1, 1000, 0, 100, 1); // tickSize == 0
    _expectRegisterRevert(sel, NEW_ASSET, token, 1, 1000, 1, 0, 1); // depositCapTicks == 0
    _expectRegisterRevert(sel, NEW_ASSET, token, 1, 1000, 1, 100, 0); // minDepositTicks == 0
    _expectRegisterRevert(sel, NEW_ASSET, token, 1, 1000, 1, MAX_DEPOSIT_CAP_TICKS + 1, 1);
    _expectRegisterRevert(sel, NEW_ASSET, token, 1, 1000, 1, 100, 101); // minDeposit > depositCap
    _expectRegisterRevert(sel, NEW_ASSET, token, 1, 0, 1, 100, 1); // extensionMultiplier == 0
    _expectRegisterRevert(sel, NEW_ASSET, token, 1, MAX_ASSET_EXTENSION_MULTIPLIER, 1, MAX_DEPOSIT_CAP_TICKS, 1); // extended cap overflow

    // Boundary: extended cap exactly at the limit is accepted.
    uint64 cap = uint64(MAX_EXTENDED_DEPOSIT_CAP_TICKS / MAX_ASSET_EXTENSION_MULTIPLIER);
    _register(NEW_ASSET, token, 1, MAX_ASSET_EXTENSION_MULTIPLIER, 1, cap, 1);
  }

  function test_updateAssetConfig_success() public {
    // LIT was registered with withdrawals disabled; enabling is the only allowed transition.
    vm.expectEmit();
    emit IEvents.UpdateAssetConfig(2, 1, 10 ** 11, 50);
    zklighter.updateAssetConfig(2, 1, 10 ** 11, 50);
    ExtendableStorage.AssetConfig memory cfg = zklighter.getAssetConfig(2);
    assertEq(cfg.withdrawalsEnabled, 1);
    assertEq(cfg.depositCapTicks, 10 ** 11);
    assertEq(cfg.minDepositTicks, 50);
    assertEq(cfg.tokenAddress, address(lit), "immutable fields preserved");
    assertEq(cfg.extensionMultiplier, 10 ** 6);
    assertEq(cfg.tickSize, 10 ** 12);

    // Native asset has tokenAddress == 0 but is still updatable.
    zklighter.updateAssetConfig(NATIVE_ASSET_INDEX, 1, 10 ** 9, 1000);
    assertEq(zklighter.getAssetConfig(NATIVE_ASSET_INDEX).depositCapTicks, 10 ** 9);
  }

  function test_updateAssetConfig_revertsForNonGovernor() public {
    vm.prank(other);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    zklighter.updateAssetConfig(2, 1, 100, 1);
  }

  function test_updateAssetConfig_revertsOnInvalidParams() public {
    bytes4 params = IZkLighter.ZkLighter_InvalidAssetConfigParams.selector;

    vm.expectRevert(IZkLighter.ZkLighter_InvalidAssetIndex.selector);
    zklighter.updateAssetConfig(NEW_ASSET, 1, 100, 1); // unregistered

    vm.expectRevert(params);
    zklighter.updateAssetConfig(2, 2, 100, 1); // withdrawalsEnabled not boolean
    vm.expectRevert(params);
    zklighter.updateAssetConfig(USDC_ASSET_INDEX, 0, 100, 1); // disabling enabled withdrawals
    vm.expectRevert(params);
    zklighter.updateAssetConfig(2, 0, 0, 1); // depositCapTicks == 0
    vm.expectRevert(params);
    zklighter.updateAssetConfig(2, 0, 100, 0); // minDepositTicks == 0
    vm.expectRevert(params);
    zklighter.updateAssetConfig(2, 0, MAX_DEPOSIT_CAP_TICKS + 1, 1);
    vm.expectRevert(params);
    zklighter.updateAssetConfig(2, 0, 100, 101); // minDeposit > depositCap

    // Extended cap overflow: register with max multiplier and a small cap, then push the cap over 2^80 / multiplier.
    address token = address(new OwnableERC20("New", "NEW", 18));
    _register(NEW_ASSET, token, 0, MAX_ASSET_EXTENSION_MULTIPLIER, 1, 2 ** 20, 1);
    vm.expectRevert(params);
    zklighter.updateAssetConfig(NEW_ASSET, 0, 2 ** 30, 1);
    zklighter.updateAssetConfig(NEW_ASSET, 0, 2 ** 24 - 1, 1);
  }

  /*//////////////////////////////////////////////////////////////
                    non-standard ERC20 deposits
  //////////////////////////////////////////////////////////////*/

  function test_deposit_excessTransferCreditsTreasuryPendingBalance() public {
    zklighter.setTreasury(treasuryAddress);
    ExcessTransferToken token = new ExcessTransferToken(7);
    _register(NEW_ASSET, address(token), 1, 1000, 1, MAX_DEPOSIT_CAP_TICKS, 1);
    token.mint(testAddress, 10_000);

    uint64 open = zklighter.openPriorityRequestCount();
    vm.startPrank(testAddress);
    token.approve(address(zklighter), 1000);
    vm.expectEmit();
    emit IEvents.Deposit(testAccountIndex, testAddress, NEW_ASSET, TxTypes.RouteType.Perps, 1000);
    zklighter.depositTest(testAddress, NEW_ASSET, TxTypes.RouteType.Perps, 1000);
    vm.stopPrank();

    assertEq(token.balanceOf(address(zklighter)), 1007);
    assertEq(zklighter.openPriorityRequestCount(), open + 1, "excess does not create a priority request");
    assertEq(zklighter.getPendingBalance(treasuryAddress, NEW_ASSET), 7, "excess credited to treasury (index 0)");
    assertEq(zklighter.getPendingBalance(testAddress, NEW_ASSET), 0);

    zklighter.withdrawPendingBalance(treasuryAddress, NEW_ASSET, 7);
    assertEq(token.balanceOf(treasuryAddress), 7 + 7, "payout itself is also an excess transfer");
    assertEq(zklighter.getPendingBalance(treasuryAddress, NEW_ASSET), 0);
  }

  function test_deposit_excessBelowTickIsRoundedDown() public {
    zklighter.setTreasury(treasuryAddress);
    ExcessTransferToken token = new ExcessTransferToken(150);
    _register(NEW_ASSET, address(token), 1, 1000, 100, MAX_DEPOSIT_CAP_TICKS, 1);
    token.mint(testAddress, 10_000);

    vm.startPrank(testAddress);
    token.approve(address(zklighter), 1000);
    zklighter.depositTest(testAddress, NEW_ASSET, TxTypes.RouteType.Perps, 1000);
    vm.stopPrank();

    assertEq(zklighter.getPendingBalance(treasuryAddress, NEW_ASSET), 1, "150 wei excess / 100 tick = 1 tick");
  }

  function test_deposit_feeOnTransferReverts() public {
    FeeOnTransferToken token = new FeeOnTransferToken(1);
    _register(NEW_ASSET, address(token), 1, 1000, 1, MAX_DEPOSIT_CAP_TICKS, 1);
    token.mint(testAddress, 10_000);

    vm.startPrank(testAddress);
    token.approve(address(zklighter), 1000);
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidDepositAmount.selector);
    zklighter.depositTest(testAddress, NEW_ASSET, TxTypes.RouteType.Perps, 1000);
    vm.stopPrank();
    assertEq(zklighter.openPriorityRequestCount(), 0);
  }

  function test_deposit_standardTokenLeavesTreasuryUntouched() public {
    zklighter.setTreasury(treasuryAddress);
    _depositUsdc(testAddress, 1_000_000);
    assertEq(zklighter.getPendingBalance(treasuryAddress, USDC_ASSET_INDEX), 0);
    assertEq(zklighter.openPriorityRequestCount(), 1);
  }

  /*//////////////////////////////////////////////////////////////
          priority request counters through real entrypoints
  //////////////////////////////////////////////////////////////*/

  function test_priorityCounters_depositCommitVerifyExecute() public {
    zklighter.verifyBatch(batch1, hex"AAAA");
    _assertCounterInvariants("start");
    assertEq(zklighter.openPriorityRequestCount(), 0);

    // 1. Deposit via ZkLighter -> priority request #0
    uint64 usdcAmount = 1_000_000;
    bytes memory depositPubData = TxTypes.writeDepositPubDataForPriorityQueue(
      testAccountIndex,
      testAddress,
      USDC_ASSET_INDEX,
      TxTypes.RouteType.Perps,
      usdcAmount
    );
    vm.startPrank(testAddress);
    usdc.approve(address(zklighter), usdcAmount);
    vm.expectEmit();
    emit IEvents.NewPriorityRequest(
      testAddress,
      0,
      TxTypes.PriorityPubDataTypeL1Deposit,
      depositPubData,
      uint64(block.timestamp + PRIORITY_EXPIRATION)
    );
    zklighter.depositTest(testAddress, USDC_ASSET_INDEX, TxTypes.RouteType.Perps, usdcAmount);
    vm.stopPrank();
    assertEq(zklighter.openPriorityRequestCount(), 1);
    assertEq(zklighter.getPriorityRequest(0).prefixHash, _paddedPrefix(bytes32(0), depositPubData));
    _assertCounterInvariants("after deposit");

    // 2. Withdraw via L1CoreMessaging -> priority request #1 chained onto #0
    bytes memory withdrawPubData = TxTypes.writeWithdrawPubDataForPriorityQueue(
      testAccountIndex,
      testAccountIndex,
      USDC_ASSET_INDEX,
      TxTypes.RouteType.Perps,
      usdcAmount
    );
    vm.prank(testAddress);
    vm.expectEmit(address(zklighter));
    emit IEvents.NewPriorityRequest(
      testAddress,
      1,
      TxTypes.PriorityPubDataTypeL1Withdraw,
      withdrawPubData,
      uint64(block.timestamp + PRIORITY_EXPIRATION)
    );
    coreMessaging.withdraw(testAccountIndex, USDC_ASSET_INDEX, TxTypes.RouteType.Perps, usdcAmount);
    assertEq(zklighter.openPriorityRequestCount(), 2);
    assertEq(zklighter.getPriorityRequest(1).prefixHash, _paddedPrefix(zklighter.getPriorityRequest(0).prefixHash, withdrawPubData));
    _assertCounterInvariants("after withdraw request");

    // 3. Commit: over-consuming or wrong prefix is rejected; correct commit advances committedPriorityRequestCount only.
    IZkLighter.CommitBatchInfo memory c = _nextCommit(batch1);
    (bytes memory log, bytes32 opsHash) = _withdrawLog(testAccountIndex, USDC_ASSET_INDEX, usdcAmount);
    c.onChainOperationsHash = opsHash;
    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = BLOB_HASH;

    c.priorityRequestCount = 3;
    c.prefixPriorityRequestHash = zklighter.getPriorityRequest(1).prefixHash;
    vm.blobhashes(blobhashes);
    vm.expectRevert(IZkLighter.ZkLighter_CommitBatchPriorityRequestCountMismatch.selector);
    zklighter.commitBatch(c, batch1);

    c.priorityRequestCount = 2;
    c.prefixPriorityRequestHash = keccak256("wrong prefix");
    vm.blobhashes(blobhashes);
    vm.expectRevert(IZkLighter.ZkLighter_PriorityRequestPrefixHashMismatch.selector);
    zklighter.commitBatch(c, batch1);

    c.prefixPriorityRequestHash = zklighter.getPriorityRequest(1).prefixHash;
    Storage.StoredBatchInfo memory batch2 = _commit(c, batch1);
    assertEq(zklighter.committedPriorityRequestCount(), 2);
    assertEq(zklighter.verifiedPriorityRequestCount(), 0);
    assertEq(zklighter.executedPriorityRequestCount(), 0);
    assertEq(zklighter.openPriorityRequestCount(), 2);
    assertEq(zklighter.getOnChainExecution(0).totalPriorityRequests, 2);
    _assertCounterInvariants("after commit");

    // 4. Verify: verified counter advances; execution deferred because of on-chain ops.
    zklighter.verifyBatch(batch2, hex"AAAA");
    assertEq(zklighter.verifiedPriorityRequestCount(), 2);
    assertEq(zklighter.executedPriorityRequestCount(), 0);
    assertEq(zklighter.openPriorityRequestCount(), 2);
    assertEq(zklighter.executedBatchesCount(), 1);
    _assertCounterInvariants("after verify");

    // 5. Execute: requests leave the open set, executed counter catches up.
    bytes[] memory logs = new bytes[](1);
    logs[0] = log;
    zklighter.executeBatches(_single(batch2), logs);
    assertEq(zklighter.executedPriorityRequestCount(), 2);
    assertEq(zklighter.openPriorityRequestCount(), 0);
    assertEq(zklighter.executedBatchesCount(), 2);
    assertEq(zklighter.pendingOnChainBatchesCount(), 0);
    assertEq(zklighter.getPendingBalance(testAddress, USDC_ASSET_INDEX), usdcAmount);
    _assertCounterInvariants("after execute");

    // 6. New request after execution gets id 2 and chains onto request #1.
    _depositUsdc(testAddress, usdcAmount);
    assertEq(zklighter.openPriorityRequestCount(), 1);
    assertEq(zklighter.getPriorityRequest(2).prefixHash, _paddedPrefix(zklighter.getPriorityRequest(1).prefixHash, depositPubData));

    // 7. Commit consuming it, then revert: committed counter rolls back, request stays open and can be re-committed.
    c = _nextCommit(batch2);
    c.priorityRequestCount = 1;
    c.prefixPriorityRequestHash = zklighter.getPriorityRequest(2).prefixHash;
    Storage.StoredBatchInfo memory batch3 = _commit(c, batch2);
    assertEq(zklighter.committedPriorityRequestCount(), 3);
    _assertCounterInvariants("after commit 3");

    zklighter.revertBatches(_single(batch3), batch2);
    assertEq(zklighter.committedPriorityRequestCount(), 2);
    assertEq(zklighter.openPriorityRequestCount(), 1);
    _assertCounterInvariants("after revert 3");

    batch3 = _commit(c, batch2);
    zklighter.verifyBatch(batch3, hex"AAAA"); // no on-chain ops -> lazy execution
    assertEq(zklighter.executedPriorityRequestCount(), 3);
    assertEq(zklighter.openPriorityRequestCount(), 0);
    assertEq(zklighter.executedBatchesCount(), 3);
    _assertCounterInvariants("end");
  }

  function test_priorityCounters_lazyExecutionOnVerifyWithoutOnChainOps() public {
    zklighter.verifyBatch(batch1, hex"AAAA");
    _depositUsdc(testAddress, 1_000_000);
    _depositUsdc(other, 2_000_000); // registers a new account for `other`
    assertEq(zklighter.addressToAccountIndex(other), testAccountIndex + 1);
    assertEq(zklighter.openPriorityRequestCount(), 2);

    IZkLighter.CommitBatchInfo memory c = _nextCommit(batch1);
    c.priorityRequestCount = 2;
    c.prefixPriorityRequestHash = zklighter.getPriorityRequest(1).prefixHash;
    Storage.StoredBatchInfo memory batch2 = _commit(c, batch1);

    vm.expectEmit();
    emit IEvents.BatchesExecuted(2, batch2.endBlockNumber);
    zklighter.verifyBatch(batch2, hex"AAAA");
    assertEq(zklighter.executedPriorityRequestCount(), 2);
    assertEq(zklighter.openPriorityRequestCount(), 0);
    assertEq(zklighter.stateRoot(), batch2.stateRoot);
    _assertCounterInvariants("after lazy execute");
  }

  /// @dev Random split of `n` queued deposits across two batches (the first with on-chain ops, the
  /// second without) keeps every counter relation intact at each step.
  function testFuzz_priorityCounters_splitAcrossBatches(uint8 nRaw, uint8 splitRaw) public {
    uint32 n = uint32(bound(nRaw, 1, 6));
    uint32 firstBatchCount = uint32(bound(splitRaw, 0, n));
    zklighter.verifyBatch(batch1, hex"AAAA");

    for (uint32 i = 0; i < n; ++i) _depositUsdc(testAddress, 1_000_000);
    assertEq(zklighter.openPriorityRequestCount(), n);
    _assertCounterInvariants("queued");

    IZkLighter.CommitBatchInfo memory c = _nextCommit(batch1);
    c.priorityRequestCount = firstBatchCount;
    if (firstBatchCount > 0) c.prefixPriorityRequestHash = zklighter.getPriorityRequest(firstBatchCount - 1).prefixHash;
    (bytes memory log, bytes32 opsHash) = _withdrawLog(testAccountIndex, USDC_ASSET_INDEX, 1);
    c.onChainOperationsHash = opsHash;
    Storage.StoredBatchInfo memory batch2 = _commit(c, batch1);
    _assertCounterInvariants("commit 2");

    c = _nextCommit(batch2);
    c.priorityRequestCount = n - firstBatchCount;
    if (n > 0) c.prefixPriorityRequestHash = zklighter.getPriorityRequest(n - 1).prefixHash;
    Storage.StoredBatchInfo memory batch3 = _commit(c, batch2);
    assertEq(zklighter.committedPriorityRequestCount(), n);
    _assertCounterInvariants("commit 3");

    zklighter.verifyBatch(batch2, hex"AAAA");
    assertEq(zklighter.executedPriorityRequestCount(), 0, "batch 2 has on-chain ops, nothing executed yet");
    _assertCounterInvariants("verify 2");
    zklighter.verifyBatch(batch3, hex"AAAA");
    assertEq(zklighter.verifiedPriorityRequestCount(), n);
    assertEq(zklighter.executedPriorityRequestCount(), 0, "batch 3 blocked behind pending batch 2");
    assertEq(zklighter.openPriorityRequestCount(), n);
    _assertCounterInvariants("verify 3");

    bytes[] memory logs = new bytes[](1);
    logs[0] = log;
    zklighter.executeBatches(_single(batch2), logs);
    assertEq(zklighter.executedPriorityRequestCount(), n, "executing batch 2 drains batch 3 lazily");
    assertEq(zklighter.executedBatchesCount(), 3);
    assertEq(zklighter.openPriorityRequestCount(), 0);
    assertEq(zklighter.pendingOnChainBatchesCount(), 0);
    _assertCounterInvariants("executed");
  }
}
