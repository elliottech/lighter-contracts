// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {ZkLighterTest} from "../contracts/test/ZkLighterTest.sol";
import {ZkLighter} from "../contracts/ZkLighter.sol";
import {AdditionalZkLighter} from "../contracts/AdditionalZkLighter.sol";
import {IZkLighter} from "../contracts/interfaces/IZkLighter.sol";
import {Storage} from "../contracts/Storage.sol";
import {OwnableERC20} from "../contracts/test/OwnableERC20.sol";
import {GovernanceTest} from "../contracts/test/GovernanceTest.sol";
import {IGovernance} from "../contracts/interfaces/IGovernance.sol";
import {IEvents} from "../contracts/interfaces/IEvents.sol";
import {ZkLighterVerifierTest} from "../contracts/test/ZkLighterVerifierTest.sol";
import {TxTypes} from "../contracts/lib/TxTypes.sol";

/// Commit, Verify and Execute tests for ZkLighter contract
contract ZkLighterTests is Test {
  OwnableERC20 usdc;
  OwnableERC20 lit;
  ZkLighterTest zklighter;
  GovernanceTest governance;
  AdditionalZkLighter additionalZkLighter;
  address testAddress;
  uint48 testAccountIndex;

  bytes pubData;
  IZkLighter.CommitBatchInfo commitBatchInfo;
  Storage.StoredBatchInfo storedBatchInfo;

  function setUp() public {
    zklighter = new ZkLighterTest();
    governance = new GovernanceTest();
    usdc = new OwnableERC20("USD Coin", "USDC", 6);
    lit = new OwnableERC20("Lighter", "LIT", 18);

    additionalZkLighter = new AdditionalZkLighter();
    zklighter.setAdditionalZkLighterAddress(address(additionalZkLighter));

    governance.overrideUSDCAddress(usdc);
    governance.overrideValidator(address(this), true);
    governance.overrideNetworkGovernor(address(this));
    zklighter.setGovernanceAddress(address(governance));

    ZkLighterVerifierTest verifier = new ZkLighterVerifierTest();
    zklighter.setVerifierAddress(address(verifier));

    pubData = hex"0071d46f9b04e49c1c89863e820571ec1fef14467de4c91087d67518e8a3f42c203c6250bad14238cb26c02973200ef5cfed332e01508064fe36cfc021d5503525b8900a6dd9bd485d615b1cc6a6dbb1bafc886aa27338b981c9edb33d77b66edbf698abe5e7e75de6bb0bf53dba2ce36990e8d5db1a9a08078fcc8f9315b20f427ce82135502c725c89380ddf685d7f00890d5d24824b818b0bb790ec49f9c12c";

    commitBatchInfo = IZkLighter.CommitBatchInfo({
      endBlockNumber: 2,
      batchSize: 1,
      startTimestamp: 3,
      endTimestamp: 5,
      priorityRequestCount: 0,
      prefixPriorityRequestHash: bytes32(0),
      onChainOperationsHash: bytes32(0),
      newStateRoot: keccak256(abi.encode("newStateRoot")),
      newValidiumRoot: keccak256(abi.encode("newValidiumRoot")),
      pubdataCommitments: pubData
    });
    storedBatchInfo = Storage.StoredBatchInfo({
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

    zklighter.setStoredBatchHash(1, keccak256(abi.encode(storedBatchInfo)));
    zklighter.setCommittedBatchesCount(1);

    testAddress = address(0x1234);
    testAccountIndex = 1234;
    zklighter.setAddressToAccountIndex(testAddress, testAccountIndex);

    vm.deal(testAddress, 1000000000000000000000 ether);
    vm.deal(address(zklighter), 10 ether);

    usdc.mint(testAddress, 1_000_000_000_000 * 10 ** 6);
    usdc.mint(address(zklighter), 1_000_000_000_000 * 10 ** 6);

    lit.mint(testAddress, 1_000_000_000 * 10 ** 18);
    lit.mint(address(zklighter), 1_000_000_000 * 10 ** 18);

    zklighter.registerDefaultAssetConfigs();

    zklighter.registerAssetConfig(2, address(lit), 0, 10 ** 6, 10 ** 12, (2 ** 50) - 1, 100);
  }

  // USDC deposit test
  function test_deposit_usdc_fail_and_success() public {
    uint16 invalidAssetIndex = 4;
    uint16 validAssetIndex = 3;
    uint256 invalidDepositAmount = 100_000;
    uint256 depositAmount = 1_000_000;

    uint256 balanceBefore = usdc.balanceOf(testAddress);

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest(testAddress, invalidAssetIndex, TxTypes.RouteType.Perps, depositAmount);

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest(testAddress, validAssetIndex, TxTypes.RouteType.Perps, depositAmount);

    vm.prank(testAddress);
    usdc.approve(address(zklighter), depositAmount);

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest(testAddress, validAssetIndex, TxTypes.RouteType.Perps, invalidDepositAmount);

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest{value: 1 ether}(testAddress, validAssetIndex, TxTypes.RouteType.Perps, depositAmount);

    vm.prank(testAddress);
    vm.expectEmit();
    emit IEvents.Deposit(testAccountIndex, testAddress, validAssetIndex, TxTypes.RouteType.Perps, uint128(depositAmount));
    zklighter.depositTest(testAddress, validAssetIndex, TxTypes.RouteType.Perps, depositAmount);

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest(testAddress, validAssetIndex, TxTypes.RouteType.Perps, depositAmount);

    uint256 balanceAfter = usdc.balanceOf(testAddress);
    assertEq(balanceBefore - balanceAfter, depositAmount, "USDC balance should be decreased by deposit amount");

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.withdrawTest(testAccountIndex, validAssetIndex, TxTypes.RouteType.Perps, 0);

    vm.prank(testAddress);
    vm.expectEmit(true, false, false, false);
    emit IEvents.NewPriorityRequest(testAddress, 0, 0, new bytes(0), 0);
    zklighter.withdrawTest(testAccountIndex, validAssetIndex, TxTypes.RouteType.Perps, uint64(depositAmount));

    vm.prank(testAddress);
    vm.expectEmit(false, false, false, false);
    emit IEvents.NewPriorityRequest(testAddress, 0, 0, new bytes(0), 0);
    zklighter.withdrawTest(testAccountIndex, validAssetIndex, TxTypes.RouteType.Spot, uint64(depositAmount));
  }

  // Eth deposit test
  function test_deposit_eth_fail_and_success() public {
    uint16 invalidAssetIndex = 3;
    uint16 validAssetIndex = 1;
    uint256 eth_invalidDepositAmount = 0.0001 ether;

    uint256 depositAmount = 100000; // 0.001 ether
    uint256 eth_depositAmount = 0.001 ether;

    uint256 balanceBefore = address(testAddress).balance;

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest{value: eth_depositAmount}(testAddress, invalidAssetIndex, TxTypes.RouteType.Perps, eth_depositAmount);

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest{value: eth_invalidDepositAmount}(testAddress, validAssetIndex, TxTypes.RouteType.Perps, eth_depositAmount);

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest{value: eth_invalidDepositAmount}(testAddress, validAssetIndex, TxTypes.RouteType.Perps, eth_invalidDepositAmount);

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest{value: eth_depositAmount}(testAddress, validAssetIndex, TxTypes.RouteType.Perps, eth_invalidDepositAmount);

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest{value: eth_depositAmount + 100}(testAddress, validAssetIndex, TxTypes.RouteType.Perps, eth_depositAmount + 100);

    vm.prank(testAddress);
    vm.expectEmit();
    emit IEvents.Deposit(testAccountIndex, testAddress, validAssetIndex, TxTypes.RouteType.Perps, uint128(depositAmount));
    zklighter.depositTest{value: eth_depositAmount}(testAddress, validAssetIndex, TxTypes.RouteType.Perps, eth_depositAmount);

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest(testAddress, validAssetIndex, TxTypes.RouteType.Perps, eth_depositAmount);

    uint256 balanceAfter = address(testAddress).balance;
    assertEq(balanceBefore - balanceAfter, eth_depositAmount, "ETH balance should be decreased by deposit amount");

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.withdrawTest(testAccountIndex, validAssetIndex, TxTypes.RouteType.Perps, 0);

    vm.prank(testAddress);
    vm.expectEmit(false, false, false, false);
    emit IEvents.NewPriorityRequest(testAddress, 0, 0, new bytes(0), 0);
    zklighter.withdrawTest(testAccountIndex, validAssetIndex, TxTypes.RouteType.Perps, uint64(depositAmount));

    vm.prank(testAddress);
    vm.expectEmit(false, false, false, false);
    emit IEvents.NewPriorityRequest(testAddress, 0, 0, new bytes(0), 0);
    zklighter.withdrawTest(testAccountIndex, validAssetIndex, TxTypes.RouteType.Spot, uint64(depositAmount));
  }

  // Commit batch test
  function test_commitBatch_success() public {
    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);

    vm.expectEmit();
    emit IEvents.BatchCommit(2, 1, 2); // expect emit log similar to this

    zklighter.commitBatch(commitBatchInfo, storedBatchInfo);

    bytes32 newStoredBatchHash = zklighter.storedBatchHashes(2);
    assertTrue(newStoredBatchHash != bytes32(0), "Stored batch hash should be set");
  }

  // LIT deposit / withdraw test
  function test_deposit_withdraw_lit_fail_and_success() public {
    uint16 invalidAssetIndex = 10;
    uint16 validAssetIndex = 2;
    uint256 invalidDepositAmount = 80 * (10 ** 12);
    uint128 baseDepositAmount = 100;
    uint256 depositAmount = baseDepositAmount * (10 ** 12);
    uint256 balanceBefore = lit.balanceOf(testAddress);
    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest(testAddress, invalidAssetIndex, TxTypes.RouteType.Spot, depositAmount);
    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest(testAddress, validAssetIndex, TxTypes.RouteType.Spot, depositAmount);
    vm.prank(testAddress);
    lit.approve(address(zklighter), depositAmount);
    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest(testAddress, validAssetIndex, TxTypes.RouteType.Spot, invalidDepositAmount);
    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest{value: 1 ether}(testAddress, validAssetIndex, TxTypes.RouteType.Spot, depositAmount);
    vm.prank(testAddress);
    vm.expectEmit();
    emit IEvents.Deposit(testAccountIndex, testAddress, validAssetIndex, TxTypes.RouteType.Spot, baseDepositAmount);
    zklighter.depositTest(testAddress, validAssetIndex, TxTypes.RouteType.Spot, depositAmount);
    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.depositTest(testAddress, validAssetIndex, TxTypes.RouteType.Spot, depositAmount);
    uint256 balanceAfter = lit.balanceOf(testAddress);
    assertEq(balanceBefore - balanceAfter, depositAmount, "LIT balance should be decreased by deposit amount");

    // try to withdraw it should revert
    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.withdrawTest(testAccountIndex, validAssetIndex, TxTypes.RouteType.Spot, uint64(baseDepositAmount));

    vm.prank(testAddress);
    vm.expectRevert();
    zklighter.withdrawTest(testAccountIndex, validAssetIndex, TxTypes.RouteType.Perps, 0);

    // enable withdrawals
    zklighter.updateAssetConfig(validAssetIndex, 1, (2 ** 50) - 1, 100);

    // try again
    vm.prank(testAddress);
    vm.expectEmit(false, false, false, false);
    emit IEvents.NewPriorityRequest(testAddress, 0, 0, new bytes(0), 0);
    zklighter.withdrawTest(testAccountIndex, validAssetIndex, TxTypes.RouteType.Perps, uint64(baseDepositAmount));

    vm.prank(testAddress);
    vm.expectEmit(false, false, false, false);
    emit IEvents.NewPriorityRequest(testAddress, 0, 0, new bytes(0), 0);
    zklighter.withdrawTest(testAccountIndex, validAssetIndex, TxTypes.RouteType.Spot, uint64(baseDepositAmount));
  }

  function test_check_default_asset_configs() public {
    ZkLighter.AssetConfig memory usdcConfig = zklighter.getAssetConfig(3);
    uint256 minDeposit = usdcConfig.minDepositTicks * usdcConfig.tickSize;
    uint256 depositCap = usdcConfig.depositCapTicks * usdcConfig.tickSize;
    assertEq(usdcConfig.tokenAddress, address(usdc), "USDC token address should be set");
    assertEq(usdcConfig.withdrawalsEnabled, 1, "USDC withdrawals should be enabled");
    assertEq(usdcConfig.extensionMultiplier, 1_000_000, "USDC extension multiplier should be 1_000_000");
    assertEq(usdcConfig.tickSize, 1, "USDC tick size should be 0.000001 USDC");
    assertEq(minDeposit, 10 ** 6, "USDC min deposit should be 1 USDC");
    assertEq(depositCap, (2 ** 60) - 1, "USDC deposit cap should be max");

    ZkLighter.AssetConfig memory ethConfig = zklighter.getAssetConfig(1);
    minDeposit = ethConfig.minDepositTicks * ethConfig.tickSize;
    depositCap = ethConfig.depositCapTicks * ethConfig.tickSize;
    assertEq(ethConfig.tokenAddress, address(0), "ETH token address should be set");
    assertEq(ethConfig.withdrawalsEnabled, 1, "ETH withdrawals should be enabled");
    assertEq(ethConfig.extensionMultiplier, 100, "ETH extension multiplier should be 100");
    assertEq(ethConfig.tickSize, 10 ** 10, "ETH tick size should be 0.00000001 ETH");
    assertEq(minDeposit, 10 ** 15, "ETH min deposit should be 0.001 ETH");
    assertEq(depositCap, 10 ** 10 * ((2 ** 60) - 1), "ETH deposit cap should be max");

    ZkLighter.AssetConfig memory litConfig = zklighter.getAssetConfig(2);
    minDeposit = litConfig.minDepositTicks * litConfig.tickSize;
    depositCap = litConfig.depositCapTicks * litConfig.tickSize;
    assertEq(litConfig.tokenAddress, address(lit), "LIT token address should be set");
    assertEq(litConfig.withdrawalsEnabled, 0, "LIT withdrawals should be disabled");
    assertEq(litConfig.extensionMultiplier, 1_000_000, "LIT extension multiplier should be 1_000_000");
    assertEq(litConfig.tickSize, 10 ** 12, "LIT tick size should be 0.000001 LIT");
    assertEq(minDeposit, 100 * (10 ** 12), "LIT min deposit should be 1 LIT");
    assertEq(depositCap, (10 ** 12) * ((2 ** 50) - 1), "LIT deposit cap should be max");
  }

  function test_commitBatch_success_priority_and_onchain() public {
    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain = commitBatchInfo;
    commitBatchInfoOnChain.onChainOperationsHash = keccak256(abi.encodePacked("onchain"));
    commitBatchInfoOnChain.priorityRequestCount = 1;
    commitBatchInfoOnChain.prefixPriorityRequestHash = keccak256(abi.encode("priority"));
    zklighter.setPriorityRequest(0, commitBatchInfoOnChain.prefixPriorityRequestHash, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain, storedBatchInfo);

    Storage.ExecutionQueueItem memory item = zklighter.getOnChainExecution(0);
    assertEq(item.batchNumber, 2, "Batch number should be set");
    assertEq(item.totalPriorityRequests, 1, "Total priority requests should be set");
    assertEq(zklighter.pendingOnChainBatchesCount(), 1, "Pending on-chain batches count should be increased");
    assertEq(zklighter.committedPriorityRequestCount(), 1, "Committed priority request count should be increased");
  }

  function test_commitBatch_fail_inactive_verifier() public {
    governance.overrideValidator(address(this), false);
    vm.expectRevert(IGovernance.ZkLighter_Governance_InvalidValidator.selector);
    zklighter.commitBatch(commitBatchInfo, storedBatchInfo);
  }

  function test_commitBatch_fail_invalid_pubdata_commitments() public {
    IZkLighter.CommitBatchInfo memory commitBatchInfoInvalid = IZkLighter.CommitBatchInfo({
      endBlockNumber: 2,
      batchSize: 1,
      startTimestamp: 0,
      endTimestamp: 0,
      priorityRequestCount: 0,
      prefixPriorityRequestHash: bytes32(0),
      onChainOperationsHash: bytes32(0),
      newStateRoot: bytes32(0),
      newValidiumRoot: bytes32(0),
      pubdataCommitments: ""
    });

    zklighter.setStoredBatchHash(1, keccak256(abi.encode(storedBatchInfo)));
    zklighter.setCommittedBatchesCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    vm.expectRevert(IZkLighter.ZkLighter_InvalidBlobCommitmentParams.selector);
    zklighter.commitBatch(commitBatchInfoInvalid, storedBatchInfo);
  }

  function test_commitBatch_fail_invalid_pubdata_mode() public {
    IZkLighter.CommitBatchInfo memory commitBatchInfoInvalid = commitBatchInfo;
    commitBatchInfoInvalid.pubdataCommitments = hex"02";
    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    vm.expectRevert(IZkLighter.ZkLighter_InvalidPubDataMode.selector);
    zklighter.commitBatch(commitBatchInfoInvalid, storedBatchInfo);
  }

  function test_commitBatch_fail_invalid_end_block_number() public {
    IZkLighter.CommitBatchInfo memory commitBatchInfoInvalid = commitBatchInfo;
    commitBatchInfoInvalid.endBlockNumber = 1;
    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    vm.expectRevert(IZkLighter.ZkLighter_NonIncreasingBlockNumber.selector);
    zklighter.commitBatch(commitBatchInfoInvalid, storedBatchInfo);
  }

  function test_commitBatch_fail_invalid_batch_size() public {
    IZkLighter.CommitBatchInfo memory commitBatchInfoInvalid = commitBatchInfo;
    commitBatchInfoInvalid.batchSize = 10;
    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    vm.expectRevert(IZkLighter.ZkLighter_InvalidBatchSize.selector);
    zklighter.commitBatch(commitBatchInfoInvalid, storedBatchInfo);
  }

  function test_commitBatch_fail_invalid_timestamp() public {
    IZkLighter.CommitBatchInfo memory commitBatchInfoInvalid = commitBatchInfo;
    commitBatchInfoInvalid.startTimestamp = 1;
    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    vm.expectRevert(IZkLighter.ZkLighter_NonIncreasingTimestamp.selector);
    zklighter.commitBatch(commitBatchInfoInvalid, storedBatchInfo);
  }

  function test_commitBatch_fail_invalid_stored_batch() public {
    zklighter.setStoredBatchHash(1, keccak256(abi.encode("invalid")));

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    vm.expectRevert(IZkLighter.ZkLighter_StoredBatchInfoMismatch.selector);
    zklighter.commitBatch(commitBatchInfo, storedBatchInfo);
  }

  function test_commitBatch_fail_invalid_priority_prefix_hash() public {
    IZkLighter.CommitBatchInfo memory commitBatchInfoInvalid = commitBatchInfo;

    bytes32 h1 = keccak256(abi.encode("invalid"));
    bytes32 h2 = keccak256(abi.encode("invalid2"));

    commitBatchInfoInvalid.priorityRequestCount = 1;
    commitBatchInfoInvalid.prefixPriorityRequestHash = h1;
    zklighter.setPriorityRequest(0, h2, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    vm.expectRevert(IZkLighter.ZkLighter_PriorityRequestPrefixHashMismatch.selector);
    zklighter.commitBatch(commitBatchInfoInvalid, storedBatchInfo);
  }

  // Verify TEST
  function test_verifyBatch_success() public {
    vm.expectEmit();
    emit IEvents.BatchVerification(1, 1, 1); // expect emit log similar to this

    vm.expectEmit();
    emit IEvents.BatchesExecuted(1, 1); // expect emit log similar to this

    assertEq(zklighter.verifiedBatchesCount(), 0);
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");
    assertEq(zklighter.verifiedBatchesCount(), 1, "Batch should be verified");
    assertTrue(zklighter.stateRoot() == storedBatchInfo.stateRoot, "Lazy execution should work");
  }

  function test_verifyBatch_fail_inactive_verifier() public {
    governance.overrideValidator(address(this), false);
    vm.expectRevert(IGovernance.ZkLighter_Governance_InvalidValidator.selector);
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");
  }

  function test_cancelOutstandingDepositsForDesertMode() public {
    uint16 assetIndex = 3;
    uint48 accountIndex = testAccountIndex;

    (uint128 balance1, ) = zklighter.getPendingBalances(assetIndex, address(testAddress));
    uint64 depositAmount = 1_000_000;

    vm.expectRevert(IZkLighter.ZkLighter_DesertModeInactive.selector);
    zklighter.cancelOutstandingDepositsForDesertMode(1, new bytes[](1));

    zklighter.setDesertMode(true);
    vm.expectRevert(IZkLighter.ZkLighter_NoOutstandingDepositsForCancelation.selector);
    zklighter.cancelOutstandingDepositsForDesertMode(1, new bytes[](1));

    zklighter.setOpenPriorityRequestCount(1);
    vm.expectRevert(IZkLighter.ZkLighter_InvalidParamsForCancelOutstandingDeposits.selector);
    zklighter.cancelOutstandingDepositsForDesertMode(2, new bytes[](2));

    vm.expectRevert(IZkLighter.ZkLighter_InvalidParamsForCancelOutstandingDeposits.selector);
    zklighter.cancelOutstandingDepositsForDesertMode(1, new bytes[](1));

    for (uint i = 0; i < 2; ++i) {
      bytes memory depositPubdata;
      if (i == 0) {
        depositPubdata = abi.encodePacked(
          uint8(TxTypes.PriorityPubDataTypeL1Deposit),
          accountIndex,
          address(testAddress),
          assetIndex,
          uint8(1), // Route type
          uint8(1), // Route type
          depositAmount
        );
      } else {
        depositPubdata = abi.encodePacked(
          uint8(TxTypes.PriorityPubDataTypeL1Deposit),
          accountIndex,
          address(testAddress),
          assetIndex,
          uint8(1), // Route type
          depositAmount
        );
      }

      bytes memory padded = new bytes(100);
      for (uint j = 0; j < depositPubdata.length; ++j) {
        padded[j] = depositPubdata[j];
      }
      bytes32 prefix = keccak256(abi.encodePacked(bytes32(0), padded));

      zklighter.setPriorityRequest(0, prefix, 10);

      bytes[] memory arr = new bytes[](1);
      arr[0] = depositPubdata;

      if (i == 0) {
        vm.expectRevert(IZkLighter.ZkLighter_DepositPubdataHashMismatch.selector);
        zklighter.cancelOutstandingDepositsForDesertMode(1, arr);
      } else {
        zklighter.cancelOutstandingDepositsForDesertMode(1, arr);
      }
    }

    (uint128 balance2, ) = zklighter.getPendingBalances(assetIndex, address(testAddress));
    assertEq(balance2 - balance1, depositAmount, "Pending balance should be increased by canceled deposit amount");
  }

  function test_verifyBatch_success_priority_and_onchain() public {
    // Verify old batch
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");

    // Commit new batch with onchain operations and priority requests
    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain = commitBatchInfo;
    commitBatchInfoOnChain.onChainOperationsHash = keccak256(abi.encodePacked("onchain"));
    commitBatchInfoOnChain.priorityRequestCount = 1;
    commitBatchInfoOnChain.prefixPriorityRequestHash = keccak256(abi.encode("priority"));
    zklighter.setPriorityRequest(0, commitBatchInfoOnChain.prefixPriorityRequestHash, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain, storedBatchInfo);

    Storage.StoredBatchInfo memory storedBatchInfoOnChain = Storage.StoredBatchInfo({
      batchNumber: 2,
      endBlockNumber: commitBatchInfoOnChain.endBlockNumber,
      batchSize: commitBatchInfoOnChain.batchSize,
      startTimestamp: commitBatchInfoOnChain.startTimestamp,
      endTimestamp: commitBatchInfoOnChain.endTimestamp,
      priorityRequestCount: commitBatchInfoOnChain.priorityRequestCount,
      prefixPriorityRequestHash: commitBatchInfoOnChain.prefixPriorityRequestHash,
      onChainOperationsHash: commitBatchInfoOnChain.onChainOperationsHash,
      stateRoot: commitBatchInfoOnChain.newStateRoot,
      validiumRoot: commitBatchInfoOnChain.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Override commitment
    zklighter.setStoredBatchHash(2, keccak256(abi.encode(storedBatchInfoOnChain)));

    // Verify new batch
    zklighter.verifyBatch(storedBatchInfoOnChain, hex"AAAA");
    assertEq(zklighter.verifiedBatchesCount(), 2, "Batch should be verified");
    assertEq(zklighter.verifiedPriorityRequestCount(), 1, "Priority request should be verified");
    assertTrue(zklighter.stateRoot() != storedBatchInfoOnChain.stateRoot, "Lazy execution should not kick in");
  }

  function test_verifyBatch_fail_invalid_proof() public {
    vm.expectRevert(IZkLighter.ZkLighter_VerifyBatchProofFailed.selector);
    zklighter.verifyBatch(storedBatchInfo, hex"AAAAAA");
  }

  function test_verifyBatch_fail_invalid_batch() public {
    Storage.StoredBatchInfo memory storedBatchInfoInvalid = storedBatchInfo;
    storedBatchInfoInvalid.commitment = keccak256(abi.encode("invalid")); // Change to an invalid one
    vm.expectRevert(IZkLighter.ZkLighter_CannotVerifyNonCommittedBatch.selector);
    zklighter.verifyBatch(storedBatchInfoInvalid, hex"AAAA");
  }

  // Execute and withdraw USDC test
  function test_executeBatches_usdc_success() public {
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");

    uint16 usdcAssetIndex = 3;
    uint64 usdcAmount = 1250;

    // Commit new batch with onchain operations and priority requests
    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain = commitBatchInfo;
    commitBatchInfoOnChain.onChainOperationsHash = keccak256(
      abi.encodePacked(bytes32(0), TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAssetIndex, usdcAmount)
    );
    commitBatchInfoOnChain.priorityRequestCount = 1;
    commitBatchInfoOnChain.prefixPriorityRequestHash = keccak256(abi.encode("priority"));
    zklighter.setPriorityRequest(0, commitBatchInfoOnChain.prefixPriorityRequestHash, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain, storedBatchInfo);

    Storage.StoredBatchInfo memory storedBatchInfoOnChain = Storage.StoredBatchInfo({
      batchNumber: 2,
      endBlockNumber: commitBatchInfoOnChain.endBlockNumber,
      batchSize: commitBatchInfoOnChain.batchSize,
      startTimestamp: commitBatchInfoOnChain.startTimestamp,
      endTimestamp: commitBatchInfoOnChain.endTimestamp,
      priorityRequestCount: commitBatchInfoOnChain.priorityRequestCount,
      prefixPriorityRequestHash: commitBatchInfoOnChain.prefixPriorityRequestHash,
      onChainOperationsHash: commitBatchInfoOnChain.onChainOperationsHash,
      stateRoot: commitBatchInfoOnChain.newStateRoot,
      validiumRoot: commitBatchInfoOnChain.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Override commitment
    zklighter.setStoredBatchHash(2, keccak256(abi.encode(storedBatchInfoOnChain)));

    // Verify new batch
    zklighter.verifyBatch(storedBatchInfoOnChain, hex"AAAA");
    assertEq(zklighter.verifiedBatchesCount(), 2, "Batch should be verified");
    assertEq(zklighter.verifiedPriorityRequestCount(), 1, "Priority request should be verified");
    assertTrue(zklighter.stateRoot() != storedBatchInfoOnChain.stateRoot, "Lazy execution should not kick in");

    // Only batch number 2 has onchain operations
    vm.expectEmit();
    emit IEvents.BatchesExecuted(2, 2); // expect emit log similar to this

    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = storedBatchInfoOnChain;

    bytes[] memory onChainPubDatas = new bytes[](1);
    // Build bytes TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAmount
    onChainPubDatas[0] = abi.encodePacked(TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAssetIndex, usdcAmount);
    zklighter.executeBatches(batches, onChainPubDatas);
    uint128 pendingBalance = zklighter.getPendingBalance(testAddress, usdcAssetIndex);
    uint256 oldUSDCBalance = usdc.balanceOf(testAddress);

    zklighter.withdrawPendingBalance(testAddress, usdcAssetIndex, usdcAmount);

    uint256 newUSDCBalance = usdc.balanceOf(testAddress);
    uint128 newPendingBalance = zklighter.getPendingBalance(testAddress, usdcAssetIndex);

    assertEq(pendingBalance, usdcAmount, "Pending balance should be increased");
    assertEq(newUSDCBalance, oldUSDCBalance + usdcAmount, "USDC balance should be increased by withdrawn amount");
    assertEq(newPendingBalance, 0, "Pending balance should be decreased after withdrawal");
    assertEq(zklighter.stateRoot(), storedBatchInfoOnChain.stateRoot, "state root should be set");
    assertEq(zklighter.validiumRoot(), storedBatchInfoOnChain.validiumRoot, "validium root should be set");
    assertEq(zklighter.pendingOnChainBatchesCount(), 0, "Pending on-chain batches count should be 0");
    assertEq(zklighter.executedOnChainBatchesCount(), 1, "Executed on-chain batches count should be 1");
    assertEq(zklighter.openPriorityRequestCount(), 0, "Open priority request count should be 0");
    assertEq(zklighter.executedPriorityRequestCount(), 1, "Executed priority request count should be 1");
    assertEq(zklighter.executedBatchesCount(), 2, "Executed batches count should be 2");
  }

  // Execute and withdraw ETH test
  function test_executeBatches_eth_success() public {
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");

    uint16 ethAssetIndex = 1;
    uint64 baseEthAmount = 12340000; // (0.1234 ETH)

    // Commit new batch with onchain operations and priority requests
    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain = commitBatchInfo;
    commitBatchInfoOnChain.onChainOperationsHash = keccak256(
      abi.encodePacked(bytes32(0), TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, ethAssetIndex, baseEthAmount)
    );
    commitBatchInfoOnChain.priorityRequestCount = 1;
    commitBatchInfoOnChain.prefixPriorityRequestHash = keccak256(abi.encode("priority"));
    zklighter.setPriorityRequest(0, commitBatchInfoOnChain.prefixPriorityRequestHash, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain, storedBatchInfo);

    Storage.StoredBatchInfo memory storedBatchInfoOnChain = Storage.StoredBatchInfo({
      batchNumber: 2,
      endBlockNumber: commitBatchInfoOnChain.endBlockNumber,
      batchSize: commitBatchInfoOnChain.batchSize,
      startTimestamp: commitBatchInfoOnChain.startTimestamp,
      endTimestamp: commitBatchInfoOnChain.endTimestamp,
      priorityRequestCount: commitBatchInfoOnChain.priorityRequestCount,
      prefixPriorityRequestHash: commitBatchInfoOnChain.prefixPriorityRequestHash,
      onChainOperationsHash: commitBatchInfoOnChain.onChainOperationsHash,
      stateRoot: commitBatchInfoOnChain.newStateRoot,
      validiumRoot: commitBatchInfoOnChain.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Override commitment
    zklighter.setStoredBatchHash(2, keccak256(abi.encode(storedBatchInfoOnChain)));

    // Verify new batch
    zklighter.verifyBatch(storedBatchInfoOnChain, hex"AAAA");
    assertEq(zklighter.verifiedBatchesCount(), 2, "Batch should be verified");
    assertEq(zklighter.verifiedPriorityRequestCount(), 1, "Priority request should be verified");
    assertTrue(zklighter.stateRoot() != storedBatchInfoOnChain.stateRoot, "Lazy execution should not kick in");

    // Only batch number 2 has onchain operations
    vm.expectEmit();
    emit IEvents.BatchesExecuted(2, 2); // expect emit log similar to this

    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = storedBatchInfoOnChain;

    bytes[] memory onChainPubDatas = new bytes[](1);
    // Build bytes TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, ethAmount
    onChainPubDatas[0] = abi.encodePacked(TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, ethAssetIndex, baseEthAmount);
    zklighter.executeBatches(batches, onChainPubDatas);
    uint128 pendingBalance = zklighter.getPendingBalance(testAddress, ethAssetIndex);
    uint256 oldETHBalance = address(testAddress).balance;

    zklighter.withdrawPendingBalance(testAddress, ethAssetIndex, baseEthAmount);

    uint256 newETHBalance = address(testAddress).balance;
    uint128 newPendingBalance = zklighter.getPendingBalance(testAddress, ethAssetIndex);

    assertEq(pendingBalance, baseEthAmount, "Pending balance should be increased");
    assertEq(newETHBalance, oldETHBalance + baseEthAmount * 10 ** 10, "ETH balance should be increased by withdrawn amount");
    assertEq(newPendingBalance, 0, "Pending balance should be decreased after withdrawal");
    assertEq(zklighter.stateRoot(), storedBatchInfoOnChain.stateRoot, "state root should be set");
    assertEq(zklighter.validiumRoot(), storedBatchInfoOnChain.validiumRoot, "validium root should be set");
    assertEq(zklighter.pendingOnChainBatchesCount(), 0, "Pending on-chain batches count should be 0");
    assertEq(zklighter.executedOnChainBatchesCount(), 1, "Executed on-chain batches count should be 1");
    assertEq(zklighter.openPriorityRequestCount(), 0, "Open priority request count should be 0");
    assertEq(zklighter.executedPriorityRequestCount(), 1, "Executed priority request count should be 1");
    assertEq(zklighter.executedBatchesCount(), 2, "Executed batches count should be 2");
  }

  function test_executeBatches_success_non_validator() public {
    // Verify old batch
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");

    uint16 usdcAssetIndex = 3;
    uint64 usdcAmount = 1000;

    // Commit new batch with onchain operations and priority requests
    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain = commitBatchInfo;
    commitBatchInfoOnChain.onChainOperationsHash = keccak256(
      abi.encodePacked(bytes32(0), TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAssetIndex, usdcAmount)
    );
    commitBatchInfoOnChain.priorityRequestCount = 1;
    commitBatchInfoOnChain.prefixPriorityRequestHash = keccak256(abi.encode("priority"));
    zklighter.setPriorityRequest(0, commitBatchInfoOnChain.prefixPriorityRequestHash, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain, storedBatchInfo);

    Storage.StoredBatchInfo memory storedBatchInfoOnChain = Storage.StoredBatchInfo({
      batchNumber: 2,
      endBlockNumber: commitBatchInfoOnChain.endBlockNumber,
      batchSize: commitBatchInfoOnChain.batchSize,
      startTimestamp: commitBatchInfoOnChain.startTimestamp,
      endTimestamp: commitBatchInfoOnChain.endTimestamp,
      priorityRequestCount: commitBatchInfoOnChain.priorityRequestCount,
      prefixPriorityRequestHash: commitBatchInfoOnChain.prefixPriorityRequestHash,
      onChainOperationsHash: commitBatchInfoOnChain.onChainOperationsHash,
      stateRoot: commitBatchInfoOnChain.newStateRoot,
      validiumRoot: commitBatchInfoOnChain.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Override commitment
    zklighter.setStoredBatchHash(2, keccak256(abi.encode(storedBatchInfoOnChain)));

    // Verify new batch
    zklighter.verifyBatch(storedBatchInfoOnChain, hex"AAAA");

    // Only batch number 2 has onchain operations

    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = storedBatchInfoOnChain;

    bytes[] memory onChainPubDatas = new bytes[](1);
    // Build bytes TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAmount
    onChainPubDatas[0] = abi.encodePacked(TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAssetIndex, usdcAmount);

    governance.overrideValidator(address(this), false);
    zklighter.executeBatches(batches, onChainPubDatas);
  }

  function test_executeBatches_success_multi() public {
    // Verify old batch
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");

    uint16 usdcAssetIndex = 3;
    uint64 usdcAmount = 1000;

    bytes32 onChainHash = keccak256(abi.encodePacked(bytes32(0), TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAssetIndex, usdcAmount));
    onChainHash = keccak256(abi.encodePacked(onChainHash, TxTypes.OnChainPubDataType.Withdraw, testAccountIndex + 1, usdcAssetIndex, usdcAmount + 1));

    // Commit new batch with onchain operations and priority requests
    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain = commitBatchInfo;
    commitBatchInfoOnChain.onChainOperationsHash = onChainHash;
    commitBatchInfoOnChain.priorityRequestCount = 1;
    commitBatchInfoOnChain.prefixPriorityRequestHash = keccak256(abi.encode("priority"));
    zklighter.setPriorityRequest(0, commitBatchInfoOnChain.prefixPriorityRequestHash, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain, storedBatchInfo);

    Storage.StoredBatchInfo memory storedBatchInfoOnChain = Storage.StoredBatchInfo({
      batchNumber: 2,
      endBlockNumber: commitBatchInfoOnChain.endBlockNumber,
      batchSize: commitBatchInfoOnChain.batchSize,
      startTimestamp: commitBatchInfoOnChain.startTimestamp,
      endTimestamp: commitBatchInfoOnChain.endTimestamp,
      priorityRequestCount: commitBatchInfoOnChain.priorityRequestCount,
      prefixPriorityRequestHash: commitBatchInfoOnChain.prefixPriorityRequestHash,
      onChainOperationsHash: commitBatchInfoOnChain.onChainOperationsHash,
      stateRoot: commitBatchInfoOnChain.newStateRoot,
      validiumRoot: commitBatchInfoOnChain.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Override commitment
    zklighter.setStoredBatchHash(2, keccak256(abi.encode(storedBatchInfoOnChain)));

    // Verify new batch
    zklighter.verifyBatch(storedBatchInfoOnChain, hex"AAAA");
    assertEq(zklighter.verifiedBatchesCount(), 2, "Batch should be verified");
    assertEq(zklighter.verifiedPriorityRequestCount(), 1, "Priority request should be verified");
    assertTrue(zklighter.stateRoot() != storedBatchInfoOnChain.stateRoot, "Lazy execution should not kick in");

    // Only batch number 2 has onchain operations

    vm.expectEmit();
    emit IEvents.BatchesExecuted(2, 2); // expect emit log similar to this

    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = storedBatchInfoOnChain;

    bytes[] memory onChainPubDatas = new bytes[](1);
    // Build bytes TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAmount
    onChainPubDatas[0] = abi.encodePacked(
      TxTypes.OnChainPubDataType.Withdraw,
      testAccountIndex,
      usdcAssetIndex,
      usdcAmount,
      TxTypes.OnChainPubDataType.Withdraw,
      testAccountIndex + 1,
      usdcAssetIndex,
      usdcAmount + 1
    );
    zklighter.executeBatches(batches, onChainPubDatas);

    assertEq(zklighter.stateRoot(), storedBatchInfoOnChain.stateRoot, "state root should be set");
    assertEq(zklighter.validiumRoot(), storedBatchInfoOnChain.validiumRoot, "validium root should be set");
    assertEq(zklighter.pendingOnChainBatchesCount(), 0, "Pending on-chain batches count should be 0");
    assertEq(zklighter.executedOnChainBatchesCount(), 1, "Executed on-chain batches count should be 1");
    assertEq(zklighter.openPriorityRequestCount(), 0, "Open priority request count should be 0");
    assertEq(zklighter.executedPriorityRequestCount(), 1, "Executed priority request count should be 1");
    assertEq(zklighter.executedBatchesCount(), 2, "Executed batches count should be 2");
  }

  function test_executeBatches_fail_invalid_params() public {
    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    bytes[] memory onChainPubDatas = new bytes[](12);

    vm.expectRevert(IZkLighter.ZkLighter_ExecuteInputLengthMismatch.selector);
    zklighter.executeBatches(batches, onChainPubDatas);
  }

  function test_executeBatches_fail_more_batch() public {
    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    bytes[] memory onChainPubDatas = new bytes[](1);

    assertEq(zklighter.pendingOnChainBatchesCount(), 0, "Pending on-chain batches count should be 0");

    vm.expectRevert(IZkLighter.ZkLighter_ExecuteInputLengthGreaterThanPendingCount.selector);
    zklighter.executeBatches(batches, onChainPubDatas);
  }

  function test_executeBatches_fail_non_verified_batch() public {
    // Verify old batch
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");

    // Commit new batch with onchain operations and priority requests
    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain = commitBatchInfo;
    commitBatchInfoOnChain.onChainOperationsHash = keccak256(abi.encode("onchain"));
    commitBatchInfoOnChain.priorityRequestCount = 1;
    commitBatchInfoOnChain.prefixPriorityRequestHash = keccak256(abi.encode("priority"));
    zklighter.setPriorityRequest(0, commitBatchInfoOnChain.prefixPriorityRequestHash, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain, storedBatchInfo);

    Storage.StoredBatchInfo memory storedBatchInfoOnChain = Storage.StoredBatchInfo({
      batchNumber: 2,
      endBlockNumber: commitBatchInfoOnChain.endBlockNumber,
      batchSize: commitBatchInfoOnChain.batchSize,
      startTimestamp: commitBatchInfoOnChain.startTimestamp,
      endTimestamp: commitBatchInfoOnChain.endTimestamp,
      priorityRequestCount: commitBatchInfoOnChain.priorityRequestCount,
      prefixPriorityRequestHash: commitBatchInfoOnChain.prefixPriorityRequestHash,
      onChainOperationsHash: commitBatchInfoOnChain.onChainOperationsHash,
      stateRoot: commitBatchInfoOnChain.newStateRoot,
      validiumRoot: commitBatchInfoOnChain.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Override commitment
    zklighter.setStoredBatchHash(2, keccak256(abi.encode(storedBatchInfoOnChain)));
    // Verify new batch
    zklighter.verifyBatch(storedBatchInfoOnChain, hex"AAAA");

    // Only batch number 2 has onchain operations
    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    storedBatchInfoOnChain.batchNumber = 3; // Set batch number to 3, which is not verified
    batches[0] = storedBatchInfoOnChain;

    bytes[] memory onChainPubDatas = new bytes[](1);

    vm.expectRevert(IZkLighter.ZkLighter_CannotExecuteNonVerifiedBatch.selector);
    zklighter.executeBatches(batches, onChainPubDatas);
  }

  function test_executeBatches_fail_wrong_batch_data() public {
    // Verify old batch
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");

    // Commit new batch with onchain operations and priority requests
    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain = commitBatchInfo;
    commitBatchInfoOnChain.onChainOperationsHash = keccak256(abi.encode("onchain"));
    commitBatchInfoOnChain.priorityRequestCount = 1;
    commitBatchInfoOnChain.prefixPriorityRequestHash = keccak256(abi.encode("priority"));
    zklighter.setPriorityRequest(0, commitBatchInfoOnChain.prefixPriorityRequestHash, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain, storedBatchInfo);

    Storage.StoredBatchInfo memory storedBatchInfoOnChain = Storage.StoredBatchInfo({
      batchNumber: 2,
      endBlockNumber: commitBatchInfoOnChain.endBlockNumber,
      batchSize: commitBatchInfoOnChain.batchSize,
      startTimestamp: commitBatchInfoOnChain.startTimestamp,
      endTimestamp: commitBatchInfoOnChain.endTimestamp,
      priorityRequestCount: commitBatchInfoOnChain.priorityRequestCount,
      prefixPriorityRequestHash: commitBatchInfoOnChain.prefixPriorityRequestHash,
      onChainOperationsHash: commitBatchInfoOnChain.onChainOperationsHash,
      stateRoot: commitBatchInfoOnChain.newStateRoot,
      validiumRoot: commitBatchInfoOnChain.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Override commitment
    zklighter.setStoredBatchHash(2, keccak256(abi.encode(storedBatchInfoOnChain)));
    // Verify new batch
    zklighter.verifyBatch(storedBatchInfoOnChain, hex"AAAA");

    // Only batch number 2 has onchain operations
    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    storedBatchInfoOnChain.stateRoot = keccak256(abi.encode("invalidStateRoot")); // Set invalid state root
    batches[0] = storedBatchInfoOnChain;

    bytes[] memory onChainPubDatas = new bytes[](1);

    vm.expectRevert(IZkLighter.ZkLighter_StoredBatchInfoMismatch.selector);
    zklighter.executeBatches(batches, onChainPubDatas);
  }

  function test_executeBatches_fail_wrong_pubdata() public {
    // Verify old batch
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");
    uint16 usdcAssetIndex = 3;
    uint64 usdcAmount = 1000;

    bytes32 onChainHash = keccak256(abi.encodePacked(bytes32(0), TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAssetIndex, usdcAmount));
    onChainHash = keccak256(abi.encodePacked(onChainHash, TxTypes.OnChainPubDataType.Withdraw, testAccountIndex + 1, usdcAssetIndex, usdcAmount + 1));
    // Commit new batch with onchain operations and priority requests
    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain = commitBatchInfo;
    commitBatchInfoOnChain.onChainOperationsHash = onChainHash;
    commitBatchInfoOnChain.priorityRequestCount = 1;
    commitBatchInfoOnChain.prefixPriorityRequestHash = keccak256(abi.encode("priority"));
    zklighter.setPriorityRequest(0, commitBatchInfoOnChain.prefixPriorityRequestHash, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain, storedBatchInfo);

    Storage.StoredBatchInfo memory storedBatchInfoOnChain = Storage.StoredBatchInfo({
      batchNumber: 2,
      endBlockNumber: commitBatchInfoOnChain.endBlockNumber,
      batchSize: commitBatchInfoOnChain.batchSize,
      startTimestamp: commitBatchInfoOnChain.startTimestamp,
      endTimestamp: commitBatchInfoOnChain.endTimestamp,
      priorityRequestCount: commitBatchInfoOnChain.priorityRequestCount,
      prefixPriorityRequestHash: commitBatchInfoOnChain.prefixPriorityRequestHash,
      onChainOperationsHash: commitBatchInfoOnChain.onChainOperationsHash,
      stateRoot: commitBatchInfoOnChain.newStateRoot,
      validiumRoot: commitBatchInfoOnChain.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Override commitment
    zklighter.setStoredBatchHash(2, keccak256(abi.encode(storedBatchInfoOnChain)));

    // Verify new batch
    zklighter.verifyBatch(storedBatchInfoOnChain, hex"AAAA");

    // Only batch number 2 has onchain operations
    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = storedBatchInfoOnChain;

    bytes[] memory onChainPubDatas = new bytes[](1);
    // Build bytes TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAmount
    onChainPubDatas[0] = abi.encodePacked(
      TxTypes.OnChainPubDataType.Withdraw,
      testAccountIndex,
      usdcAssetIndex,
      usdcAmount,
      TxTypes.OnChainPubDataType.Withdraw,
      testAccountIndex + 1,
      usdcAssetIndex,
      usdcAmount + 2 // Wrong amount
    );

    vm.expectRevert(IZkLighter.ZkLighter_OnChainOperationsHashMismatch.selector);
    zklighter.executeBatches(batches, onChainPubDatas);
  }

  function test_executeBatches_fail_wrong_pubdata_type() public {
    // Verify old batch
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");

    uint16 usdcAssetIndex = 3;
    uint64 usdcAmount = 1000;

    bytes32 onChainHash = keccak256(abi.encodePacked(bytes32(0), TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAssetIndex, usdcAmount));
    onChainHash = keccak256(abi.encodePacked(onChainHash, TxTypes.OnChainPubDataType.Withdraw, testAccountIndex + 1, usdcAssetIndex, usdcAmount + 1));

    // Commit new batch with onchain operations and priority requests
    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain = commitBatchInfo;
    commitBatchInfoOnChain.onChainOperationsHash = onChainHash;
    commitBatchInfoOnChain.priorityRequestCount = 1;
    commitBatchInfoOnChain.prefixPriorityRequestHash = keccak256(abi.encode("priority"));
    zklighter.setPriorityRequest(0, commitBatchInfoOnChain.prefixPriorityRequestHash, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain, storedBatchInfo);

    Storage.StoredBatchInfo memory storedBatchInfoOnChain = Storage.StoredBatchInfo({
      batchNumber: 2,
      endBlockNumber: commitBatchInfoOnChain.endBlockNumber,
      batchSize: commitBatchInfoOnChain.batchSize,
      startTimestamp: commitBatchInfoOnChain.startTimestamp,
      endTimestamp: commitBatchInfoOnChain.endTimestamp,
      priorityRequestCount: commitBatchInfoOnChain.priorityRequestCount,
      prefixPriorityRequestHash: commitBatchInfoOnChain.prefixPriorityRequestHash,
      onChainOperationsHash: commitBatchInfoOnChain.onChainOperationsHash,
      stateRoot: commitBatchInfoOnChain.newStateRoot,
      validiumRoot: commitBatchInfoOnChain.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Override commitment
    zklighter.setStoredBatchHash(2, keccak256(abi.encode(storedBatchInfoOnChain)));

    // Verify new batch
    zklighter.verifyBatch(storedBatchInfoOnChain, hex"AAAA");

    // Only batch number 2 has onchain operations
    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = storedBatchInfoOnChain;

    bytes[] memory onChainPubDatas = new bytes[](1);
    // Build bytes TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAmount
    onChainPubDatas[0] = abi.encodePacked(
      uint8(TxTypes.OnChainPubDataType.Withdraw) + 1,
      testAccountIndex,
      usdcAssetIndex,
      usdcAmount,
      TxTypes.OnChainPubDataType.Withdraw,
      testAccountIndex + 1,
      usdcAssetIndex,
      usdcAmount + 1
    );

    vm.expectRevert(IZkLighter.ZkLighter_InvalidPubDataType.selector);
    zklighter.executeBatches(batches, onChainPubDatas);
  }

  function test_executeBatches_fail_wrong_pubdata_length() public {
    // Verify old batch
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");

    uint16 usdcAssetIndex = 3;
    uint64 usdcAmount = 1000;

    bytes32 onChainHash = keccak256(abi.encodePacked(bytes32(0), TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAssetIndex, usdcAmount));
    onChainHash = keccak256(abi.encodePacked(onChainHash, TxTypes.OnChainPubDataType.Withdraw, testAccountIndex + 1, usdcAssetIndex, usdcAmount + 1));

    // Commit new batch with onchain operations and priority requests
    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain = commitBatchInfo;
    commitBatchInfoOnChain.onChainOperationsHash = onChainHash;
    commitBatchInfoOnChain.priorityRequestCount = 1;
    commitBatchInfoOnChain.prefixPriorityRequestHash = keccak256(abi.encode("priority"));
    zklighter.setPriorityRequest(0, commitBatchInfoOnChain.prefixPriorityRequestHash, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain, storedBatchInfo);

    Storage.StoredBatchInfo memory storedBatchInfoOnChain = Storage.StoredBatchInfo({
      batchNumber: 2,
      endBlockNumber: commitBatchInfoOnChain.endBlockNumber,
      batchSize: commitBatchInfoOnChain.batchSize,
      startTimestamp: commitBatchInfoOnChain.startTimestamp,
      endTimestamp: commitBatchInfoOnChain.endTimestamp,
      priorityRequestCount: commitBatchInfoOnChain.priorityRequestCount,
      prefixPriorityRequestHash: commitBatchInfoOnChain.prefixPriorityRequestHash,
      onChainOperationsHash: commitBatchInfoOnChain.onChainOperationsHash,
      stateRoot: commitBatchInfoOnChain.newStateRoot,
      validiumRoot: commitBatchInfoOnChain.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Override commitment
    zklighter.setStoredBatchHash(2, keccak256(abi.encode(storedBatchInfoOnChain)));

    // Verify new batch
    zklighter.verifyBatch(storedBatchInfoOnChain, hex"AAAA");

    // Only batch number 2 has onchain operations
    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = storedBatchInfoOnChain;

    bytes[] memory onChainPubDatas = new bytes[](1);
    // Build bytes TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAmount
    onChainPubDatas[0] = abi.encodePacked(
      TxTypes.OnChainPubDataType.Withdraw,
      testAccountIndex,
      usdcAssetIndex,
      usdcAmount,
      TxTypes.OnChainPubDataType.Withdraw,
      testAccountIndex + 1,
      usdcAssetIndex,
      usdcAmount + 1,
      uint8(1) // Extra byte at the end
    );

    vm.expectRevert(IZkLighter.ZkLighter_InvalidPubDataLength.selector);
    zklighter.executeBatches(batches, onChainPubDatas);
  }

  function test_executeBatches_fail_skip_queue() public {
    // Verify old batch
    zklighter.verifyBatch(storedBatchInfo, hex"AAAA");

    uint16 usdcAssetIndex = 3;
    uint64 usdcAmount = 1000;

    bytes32 onChainHash = keccak256(abi.encodePacked(bytes32(0), TxTypes.OnChainPubDataType.Withdraw, testAccountIndex, usdcAssetIndex, usdcAmount));
    onChainHash = keccak256(abi.encodePacked(onChainHash, TxTypes.OnChainPubDataType.Withdraw, testAccountIndex + 1, usdcAssetIndex, usdcAmount + 1));
    // Commit new batch with onchain operations and priority requests
    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain = commitBatchInfo;
    commitBatchInfoOnChain.onChainOperationsHash = onChainHash;
    commitBatchInfoOnChain.priorityRequestCount = 1;
    commitBatchInfoOnChain.prefixPriorityRequestHash = keccak256(abi.encode("priority"));
    zklighter.setPriorityRequest(0, commitBatchInfoOnChain.prefixPriorityRequestHash, 10);
    zklighter.setOpenPriorityRequestCount(1);

    bytes32[] memory blobhashes = new bytes32[](1);
    blobhashes[0] = bytes32(0x016542a1e23b3617419d3da0814265983e60fdc0c75759656c8229a828ffa07c);
    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain, storedBatchInfo);

    Storage.StoredBatchInfo memory storedBatchInfoOnChain = Storage.StoredBatchInfo({
      batchNumber: 2,
      endBlockNumber: commitBatchInfoOnChain.endBlockNumber,
      batchSize: commitBatchInfoOnChain.batchSize,
      startTimestamp: commitBatchInfoOnChain.startTimestamp,
      endTimestamp: commitBatchInfoOnChain.endTimestamp,
      priorityRequestCount: commitBatchInfoOnChain.priorityRequestCount,
      prefixPriorityRequestHash: commitBatchInfoOnChain.prefixPriorityRequestHash,
      onChainOperationsHash: commitBatchInfoOnChain.onChainOperationsHash,
      stateRoot: commitBatchInfoOnChain.newStateRoot,
      validiumRoot: commitBatchInfoOnChain.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Override commitment
    zklighter.setStoredBatchHash(2, keccak256(abi.encode(storedBatchInfoOnChain)));

    // Verify new batch
    zklighter.verifyBatch(storedBatchInfoOnChain, hex"AAAA");

    bytes32 onChainHash2 = keccak256(
      abi.encodePacked(bytes32(0), TxTypes.OnChainPubDataType.Withdraw, testAccountIndex + 2, usdcAssetIndex, usdcAmount + 2)
    );
    onChainHash2 = keccak256(
      abi.encodePacked(onChainHash2, TxTypes.OnChainPubDataType.Withdraw, testAccountIndex + 3, usdcAssetIndex, usdcAmount + 3)
    );

    IZkLighter.CommitBatchInfo memory commitBatchInfoOnChain2 = IZkLighter.CommitBatchInfo({
      endBlockNumber: 3,
      batchSize: 1,
      startTimestamp: 5,
      endTimestamp: 10,
      priorityRequestCount: 0,
      prefixPriorityRequestHash: keccak256(abi.encode("priority")),
      onChainOperationsHash: onChainHash2,
      newStateRoot: keccak256(abi.encode("newStateRoot2")),
      newValidiumRoot: keccak256(abi.encode("newValidiumRoot2")),
      pubdataCommitments: pubData
    });

    vm.blobhashes(blobhashes);
    zklighter.commitBatch(commitBatchInfoOnChain2, storedBatchInfoOnChain);

    Storage.StoredBatchInfo memory storedBatchInfoOnChain2 = Storage.StoredBatchInfo({
      batchNumber: 3,
      endBlockNumber: commitBatchInfoOnChain2.endBlockNumber,
      batchSize: commitBatchInfoOnChain2.batchSize,
      startTimestamp: commitBatchInfoOnChain2.startTimestamp,
      endTimestamp: commitBatchInfoOnChain2.endTimestamp,
      priorityRequestCount: commitBatchInfoOnChain2.priorityRequestCount,
      prefixPriorityRequestHash: commitBatchInfoOnChain2.prefixPriorityRequestHash,
      onChainOperationsHash: commitBatchInfoOnChain2.onChainOperationsHash,
      stateRoot: commitBatchInfoOnChain2.newStateRoot,
      validiumRoot: commitBatchInfoOnChain2.newValidiumRoot,
      commitment: bytes32(0)
    });
    // Override commitment
    zklighter.setStoredBatchHash(3, keccak256(abi.encode(storedBatchInfoOnChain2)));

    // Verify new batch
    zklighter.verifyBatch(storedBatchInfoOnChain2, hex"AAAA");

    // batch number 2 and 3 have onchain operations
    Storage.StoredBatchInfo[] memory batches = new Storage.StoredBatchInfo[](1);
    batches[0] = storedBatchInfoOnChain2;

    bytes[] memory onChainPubDatas = new bytes[](1);

    // Send batch 3 to execute, skipping batch 2
    vm.expectRevert(IZkLighter.ZkLighter_BatchNotInOnChainQueue.selector);
    zklighter.executeBatches(batches, onChainPubDatas);
  }
}
