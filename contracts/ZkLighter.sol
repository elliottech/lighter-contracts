// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "./ExtendableStorage.sol";
import "./Storage.sol";
import "./interfaces/IDesertVerifier.sol";
import "./interfaces/IZkLighter.sol";
import "./interfaces/IZkLighterVerifier.sol";
import "./interfaces/IOpenVmZkLighterVerifier.sol";
import "./lib/Bytes.sol";
import "./lib/TxTypes.sol";
import {IL1CoreMessaging} from "./interfaces/IL1CoreMessaging.sol";
import {IL1InteropManager} from "./interfaces/IL1InteropManager.sol";
import {LIGHTER_CORE_SYSTEM_ADDR} from "./Constants.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title zkLighter Contract
/// @author zkLighter Team
/// @dev Portions (the upgrade hooks and `delegateAdditional`) are adapted from Matter Labs' zkSync Lite
/// (https://github.com/matter-labs/zksync/blob/master/contracts/contracts/ZkSync.sol), licensed under
/// MIT OR Apache-2.0. See THIRD_PARTY_NOTICES.md.
contract ZkLighter is IZkLighter, Storage, ReentrancyGuardUpgradeable, ExtendableStorage {
  uint256 internal constant COMMIT_BATCH_INFO_LENGTH = 0x2a0;

  uint256 internal constant TAIL_COMMITMENT_OFFSET = COMMIT_BATCH_INFO_LENGTH + 0x20;

  address internal immutable zklighterImplementation;

  /// @dev Locks the implementation contract so that it can only be used behind a proxy.
  constructor() {
    zklighterImplementation = address(this);

    _disableInitializers();
  }

  /// @notice ZkLighter contract upgrade. Can be external because Proxy contract intercepts illegal calls of this function
  /// @param upgradeParameters Encoded representation of upgrade parameters
  function upgrade(bytes calldata upgradeParameters) external nonReentrant {
    if (address(this) == zklighterImplementation) {
      revert ZkLighter_OnlyProxyCanCallUpgrade();
    }

    (
      address _additionalZkLighter,
      address _desertVerifier,
      address _stateRootUpgradeVerifier,
      address _coreMessaging,
      address _desertBatchVerifier
    ) = abi.decode(upgradeParameters, (address, address, address, address, address));

    if (_additionalZkLighter != address(0)) {
      if (!_hasCode(_additionalZkLighter)) {
        revert ZkLighter_InvalidUpgradeParameters();
      }
      additionalZkLighter = _additionalZkLighter;
    }

    if (_desertVerifier != address(0)) {
      if (!_hasCode(_desertVerifier)) {
        revert ZkLighter_InvalidUpgradeParameters();
      }
      desertVerifier = IDesertVerifier(_desertVerifier);
    }

    if (_stateRootUpgradeVerifier != address(0)) {
      if (!_hasCode(_stateRootUpgradeVerifier)) {
        revert ZkLighter_InvalidUpgradeParameters();
      }
      stateRootUpgradeVerifier = IZkLighterStateRootUpgradeVerifier(_stateRootUpgradeVerifier);
    }

    // No _hasCode check: ZkLighter must be upgraded before L1CoreMessaging is deployed.
    if (_coreMessaging != address(0)) {
      coreMessaging = _coreMessaging;
    }

    if (_desertBatchVerifier != address(0)) {
      if (!_hasCode(_desertBatchVerifier)) {
        revert ZkLighter_InvalidUpgradeParameters();
      }
      desertBatchVerifier = IOpenVmZkLighterVerifier(_desertBatchVerifier);
    }
  }

  /// @inheritdoc IZkLighter
  function updateCoreStateRoot(
    StoredBatchInfo calldata _lastStoredBatch,
    LighterStateRootPreimage calldata stateRootPreimage,
    bytes32 newCoreStateRoot,
    bytes32 newValidiumRoot,
    bytes calldata proof
  ) external {
    delegateAdditional();
  }

  function createExitCommitment(
    uint256 stateRoot,
    uint48 _accountIndex,
    uint48 _masterAccountIndex,
    address _l1Address,
    uint32 _assetIndex,
    uint128 _totalBaseAmount
  ) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(stateRoot, _accountIndex, _masterAccountIndex, _l1Address, _assetIndex, _totalBaseAmount));
  }

  /// @notice Performs exit from zkLighter in desert mode
  function performDesert(
    uint48 _accountIndex,
    address _l1Address,
    uint32 _assetIndex,
    uint128 _totalBaseAmount,
    bytes calldata proof
  ) external nonReentrant {
    // Must be in desert mode
    if (!desertMode) {
      revert ZkLighter_DesertError();
    }

    if (accountPerformedDesertForAsset[_assetIndex][_accountIndex]) {
      revert ZkLighter_DesertError();
    }

    uint48 masterAccountIndex = IL1CoreMessaging(coreMessaging).getAccountIndexFromAddress(_l1Address);
    if (masterAccountIndex == NIL_ACCOUNT_INDEX) {
      revert ZkLighter_DesertError();
    }

    // System accounts pass their current role address, which receives the exit. Their Core
    // leaves commit the zero owner address, so the exit commitment uses address(0) for them.
    address leafL1Address = _l1Address;
    if (masterAccountIndex == TREASURY_ACCOUNT_INDEX || masterAccountIndex == INSURANCE_FUND_OPERATOR_ACCOUNT_INDEX) {
      leafL1Address = address(0);
    }

    uint256[] memory inputs = new uint256[](1);
    bytes32 commitment = createExitCommitment(
      uint256(coreStateRoot),
      _accountIndex,
      masterAccountIndex,
      leafL1Address,
      _assetIndex,
      _totalBaseAmount
    );
    inputs[0] = uint256(commitment) % BN254_MODULUS;
    bool success = desertVerifier.Verify(proof, inputs);
    if (!success) {
      revert ZkLighter_DesertError();
    }

    _persistDesertL1CallHash(_l1Address, _assetIndex, _totalBaseAmount);

    accountPerformedDesertForAsset[_assetIndex][_accountIndex] = true;
  }

  /// @inheritdoc IZkLighter
  /// @dev Each deposit is refunded to the toAddress in its pubdata, including deposits to
  /// system accounts (treasury, insurance fund). A deposit whose pubdata carries no toAddress
  /// can only target a system account; its refund goes to that account's current role address,
  /// resolved via L1CoreMessaging.getSystemAddress, which reverts for any other account.
  function cancelOutstandingDepositsForDesertMode(uint64 _n, bytes[] calldata _priorityPubData) external nonReentrant {
    if (!desertMode) {
      revert ZkLighter_DesertError();
    }
    if (committedBatchesCount != executedBatchesCount || verifiedBatchesCount != executedBatchesCount || pendingOnChainBatchesCount != 0) {
      revert ZkLighter_DesertPipelineNotCaughtUp();
    }
    if (openPriorityRequestCount == 0 || _n == 0) {
      revert ZkLighter_DesertError();
    }
    if (_n > openPriorityRequestCount || _n != _priorityPubData.length) {
      revert ZkLighter_DesertError();
    }

    uint256 startIndex = executedPriorityRequestCount;

    bytes32 pubDataPrefixHash = bytes32(0);
    if (executedPriorityRequestCount > 0) {
      pubDataPrefixHash = priorityRequests[executedPriorityRequestCount - 1].prefixHash;
    }

    for (uint256 i = 0; i != _n; ++i) {
      bytes calldata pubData = _priorityPubData[i];
      uint256 pubDataLen = pubData.length;
      if (pubDataLen == 0 || pubDataLen > MAX_PRIORITY_REQUEST_PUBDATA_SIZE) {
        revert ZkLighter_DesertError();
      }

      pubDataPrefixHash = _hashPubDataPrefixed(pubDataPrefixHash, pubData);

      if (pubDataPrefixHash != priorityRequests[startIndex + i].prefixHash) {
        revert ZkLighter_DesertError();
      }

      if (uint8(pubData[0]) == TxTypes.PriorityPubDataTypeL1Deposit) {
        if (pubDataLen != TxTypes.DEPOSIT_PUB_DATA_SIZE) {
          revert ZkLighter_DesertError();
        }
        (uint48 accountIndex, address toAddress, uint32 assetIndex, uint64 baseAmount) = TxTypes.readDepositFromCalldata(pubData);
        if (toAddress == address(0)) {
          toAddress = IL1CoreMessaging(coreMessaging).getSystemAddress(accountIndex);
        }
        _persistDesertL1CallHash(toAddress, assetIndex, baseAmount);
      }
    }

    openPriorityRequestCount -= _n;
    executedPriorityRequestCount += _n;
  }

  function _persistDesertL1CallHash(address toAddress, uint32 assetIndex, uint128 baseAmount) internal {
    uint256 nonce = desertModeNonce;
    if (nonce == 0) nonce = type(uint256).max;
    unchecked {
      desertModeNonce = nonce - 1;
    }

    bytes32 l1CallHash;
    if (assetIndex == NATIVE_ASSET_INDEX) {
      uint256 value = uint256(baseAmount) * uint256(ETH_TICK_SIZE);
      l1CallHash = _computeL1CallHash({_l2Sender: LIGHTER_CORE_SYSTEM_ADDR, to: toAddress, value: value, _nonce: nonce, data: ""});
    } else {
      address l1InteropManager = address(IL1CoreMessaging(coreMessaging).INTEROP_MANAGER());
      bytes memory data = abi.encodeCall(IL1InteropManager.receiveFromCore, (assetIndex, toAddress, baseAmount));
      l1CallHash = _computeL1CallHash({_l2Sender: LIGHTER_CORE_SYSTEM_ADDR, to: l1InteropManager, value: 0, _nonce: nonce, data: data});
    }
    _persistL1CallHash(l1CallHash);
    emit DesertL1CallHashPersisted(l1CallHash, toAddress, assetIndex, baseAmount);
  }

  /// @inheritdoc IZkLighter
  function commitBatch(
    CommitBatchInfo calldata newBatchData,
    StoredBatchInfo calldata lastStoredBatch,
    bytes calldata pubdataCommitments
  ) external nonReentrant onlyActive {
    governance.isActiveValidator(msg.sender);

    {
      if (pubdataCommitments.length == 0) {
        revert ZkLighter_InvalidBlobCommitmentParams();
      }
      uint8 pubDataMode = uint8(bytes1(pubdataCommitments[0]));
      if (pubDataMode != uint8(PubDataMode.Blob)) {
        revert ZkLighter_InvalidPubDataMode();
      }
      if (newBatchData.endBlockNumber != lastStoredBatch.commitBatchInfo.endBlockNumber + newBatchData.batchSize) {
        revert ZkLighter_InvalidBatchSize();
      }
      if (newBatchData.endEvmBlockNumber != lastStoredBatch.commitBatchInfo.endEvmBlockNumber + newBatchData.evmNumBlocks) {
        revert ZkLighter_InvalidBatchSize();
      }
      if (newBatchData.oldEvmBlockhash != lastStoredBatch.commitBatchInfo.newEvmBlockhash) {
        revert ZkLighter_InvalidOldEvmBlockhash();
      }
      if (newBatchData.startTimestamp < lastStoredBatch.commitBatchInfo.endTimestamp || newBatchData.endTimestamp < newBatchData.startTimestamp) {
        revert ZkLighter_NonIncreasingTimestamp();
      }
      if (storedBatchHashes[committedBatchesCount] != hashStoredBatchInfo(lastStoredBatch)) {
        revert ZkLighter_StoredBatchInfoMismatch();
      }
      uint64 lastPriorityRequestToCommitCount = committedPriorityRequestCount + newBatchData.priorityRequestCount;
      uint64 lastEvmPriorityRequestToCommitCount = committedEvmPriorityRequestCount + newBatchData.evmPriorityRequestCount;
      if (executedPriorityRequestCount + openPriorityRequestCount < lastPriorityRequestToCommitCount) {
        revert ZkLighter_CommitBatchPriorityRequestCountMismatch();
      }
      if (executedEvmPriorityRequestCount + openEvmPriorityRequestCount < lastEvmPriorityRequestToCommitCount) {
        revert ZkLighter_CommitBatchEvmPriorityRequestCountMismatch();
      }
      if (
        lastPriorityRequestToCommitCount >= 1 &&
        priorityRequests[lastPriorityRequestToCommitCount - 1].prefixHash != newBatchData.prefixPriorityRequestHash
      ) {
        revert ZkLighter_PriorityRequestPrefixHashMismatch();
      }
      if (
        lastEvmPriorityRequestToCommitCount >= 1 &&
        evmPriorityRequests[lastEvmPriorityRequestToCommitCount - 1].prefixHash != newBatchData.prefixEvmPriorityRequestHash
      ) {
        revert ZkLighter_EvmPriorityRequestPrefixHashMismatch();
      }
    }

    bytes32 oldStateRoot = _getStateRoot(lastStoredBatch);

    {
      committedBatchesCount++;
      _writeStreamUpdate({
        s: toCoreLiveness,
        baseBatchNumber: committedBatchesCount - 1,
        batchNumber: committedBatchesCount,
        initCount: newBatchData.initToCoreWritesCount,
        doneCount: newBatchData.doneToCoreWritesCount
      });
      _writeStreamUpdate({
        s: toEvmLiveness,
        baseBatchNumber: committedBatchesCount - 1,
        batchNumber: committedBatchesCount,
        initCount: newBatchData.initToEvmWritesCount,
        doneCount: newBatchData.doneToEvmWritesCount
      });
      if (newBatchData.onChainOperationsHash != bytes32(0)) {
        onChainExecutionQueue[executedOnChainBatchesCount + pendingOnChainBatchesCount] = ExecutionQueueItem({
          batchNumber: committedBatchesCount,
          totalPriorityRequests: committedPriorityRequestCount + newBatchData.priorityRequestCount,
          totalEvmPriorityRequests: committedEvmPriorityRequestCount + newBatchData.evmPriorityRequestCount
        });
        pendingOnChainBatchesCount++;
      }
    }

    bytes32 storedBatchHash = _computeStoredBatchHash({
      newBatchData: newBatchData,
      batchNumber: committedBatchesCount,
      oldStateRoot: oldStateRoot,
      aggregatedBlobCommitment: _processBlobs(pubdataCommitments[1:])
    });
    storedBatchHashes[committedBatchesCount] = storedBatchHash;

    committedPriorityRequestCount += newBatchData.priorityRequestCount;
    committedEvmPriorityRequestCount += newBatchData.evmPriorityRequestCount;
    emit BatchCommit(
      committedBatchesCount,
      newBatchData.batchSize,
      newBatchData.endBlockNumber,
      newBatchData.endEvmBlockNumber,
      newBatchData.newEvmBlockhash
    );
  }

  function _writeStreamUpdate(
    mapping(uint64 => BatchStreamUpdate) storage s,
    uint64 baseBatchNumber,
    uint64 batchNumber,
    uint32 initCount,
    uint32 doneCount
  ) internal {
    uint64 expirationTimestamp = uint64(block.timestamp + INTEROP_WRITE_STREAM_EXPIRATION);

    BatchStreamUpdate storage prev = s[baseBatchNumber];

    uint64 newInitTotal = prev.initWritesTotalCount + initCount;
    uint64 newDoneTotal = prev.doneWritesTotalCount + doneCount;
    assert(newInitTotal >= newDoneTotal);

    // init and done cumulative counts must be monotonic
    if (batchNumber > 0) {
      assert(newInitTotal >= s[batchNumber - 1].initWritesTotalCount);
      assert(newDoneTotal >= s[batchNumber - 1].doneWritesTotalCount);
    }

    s[batchNumber] = BatchStreamUpdate({
      expirationTimestamp: expirationTimestamp,
      initWritesTotalCount: newInitTotal,
      doneWritesTotalCount: newDoneTotal
    });
  }

  /// @inheritdoc IZkLighter
  function desertVerifyBatch(
    DesertBatchInfo calldata newBatchData,
    StoredBatchInfo calldata baseStoredBatch,
    bytes calldata proof
  ) external nonReentrant {
    {
      if (!desertMode) {
        revert ZkLighter_DesertModeInactive();
      }
      if (committedBatchesCount != executedBatchesCount || verifiedBatchesCount != executedBatchesCount || pendingOnChainBatchesCount != 0) {
        revert ZkLighter_DesertPipelineNotCaughtUp();
      }
    }

    // base batch checks
    {
      if (storedBatchHashes[baseStoredBatch.batchNumber] != hashStoredBatchInfo(baseStoredBatch)) {
        revert ZkLighter_StoredBatchInfoMismatch();
      }
      if (baseStoredBatch.batchNumber < executedBatchesCount - desertModeBatchesCount) {
        revert ZkLighter_DesertBaseBatchTooOld();
      }
      // the following are a result of the check above, added for explicitness
      assert(baseStoredBatch.commitBatchInfo.endBlockNumber == lastVerifiedEndBlockNumber);
    }

    if (desertModeBatchesCount == 0) {
      assert(baseStoredBatch.batchNumber == executedBatchesCount);
      desertEvmPriorityRequestCount[baseStoredBatch.batchNumber] = executedEvmPriorityRequestCount;
    }
    uint64 lastEvmPriorityRequestToExecuteCount = desertEvmPriorityRequestCount[baseStoredBatch.batchNumber] + newBatchData.evmPriorityRequestCount;
    uint256 evmNumBlocks = newBatchData.doneToCoreWritesCount + newBatchData.doneToEvmWritesCount + newBatchData.evmPriorityRequestCount;
    uint256 endEvmBlockNumber = baseStoredBatch.commitBatchInfo.endEvmBlockNumber + evmNumBlocks;

    // new batch evm checks
    {
      if (endEvmBlockNumber <= lastVerifiedEndEvmBlockNumber) {
        revert ZkLighter_DesertNonIncreasingEvmBlockNumber();
      }
      if (newBatchData.oldEvmBlockhash != baseStoredBatch.commitBatchInfo.newEvmBlockhash) {
        revert ZkLighter_InvalidOldEvmBlockhash();
      }

      // evm priority request checks
      if (lastEvmPriorityRequestToExecuteCount < executedEvmPriorityRequestCount) {
        revert ZkLighter_CommitBatchEvmPriorityRequestCountMismatch();
      }
      if (executedEvmPriorityRequestCount + openEvmPriorityRequestCount < lastEvmPriorityRequestToExecuteCount) {
        revert ZkLighter_CommitBatchEvmPriorityRequestCountMismatch();
      }
      if (
        lastEvmPriorityRequestToExecuteCount >= 1 &&
        evmPriorityRequests[lastEvmPriorityRequestToExecuteCount - 1].prefixHash != newBatchData.prefixEvmPriorityRequestHash
      ) {
        revert ZkLighter_EvmPriorityRequestPrefixHashMismatch();
      }
    }

    uint64 batchNumber = committedBatchesCount + 1;

    // commit and verify
    {
      (bytes32 commitment, bytes32 storedBatchHash) = _computeCommitments({
        newBatchData: newBatchData,
        baseStoredBatch: baseStoredBatch,
        batchNumber: batchNumber,
        oldStateRoot: _getStateRoot(baseStoredBatch),
        currentCoreStateRoot: coreStateRoot,
        currentValidiumRoot: validiumRoot
      });
      if (!_verifyBatch(desertBatchVerifier, commitment, proof)) {
        revert ZkLighter_DesertBatchProofFailed();
      }
      storedBatchHashes[batchNumber] = storedBatchHash;
      _evmL1CallsRoots[batchNumber] = newBatchData.evmL1CallsRoot;
    }

    // store updates
    {
      _writeStreamUpdate({
        s: toCoreLiveness,
        baseBatchNumber: baseStoredBatch.batchNumber,
        batchNumber: batchNumber,
        initCount: 0,
        doneCount: newBatchData.doneToCoreWritesCount
      });
      _writeStreamUpdate({
        s: toEvmLiveness,
        baseBatchNumber: baseStoredBatch.batchNumber,
        batchNumber: batchNumber,
        initCount: 0,
        doneCount: newBatchData.doneToEvmWritesCount
      });

      committedBatchesCount = batchNumber;
      verifiedBatchesCount = batchNumber;
      executedBatchesCount = batchNumber;

      desertModeBatchesCount += 1;

      openEvmPriorityRequestCount -= lastEvmPriorityRequestToExecuteCount - executedEvmPriorityRequestCount;
      committedEvmPriorityRequestCount = lastEvmPriorityRequestToExecuteCount;
      verifiedEvmPriorityRequestCount = lastEvmPriorityRequestToExecuteCount;
      executedEvmPriorityRequestCount = lastEvmPriorityRequestToExecuteCount;
      desertEvmPriorityRequestCount[batchNumber] = lastEvmPriorityRequestToExecuteCount;

      lastVerifiedStateRoot = newBatchData.newStateRoot;
      lastVerifiedEndEvmBlockNumber = endEvmBlockNumber;
      lastVerifiedEvmBlockhash = newBatchData.newEvmBlockhash;
      stateRoot = newBatchData.newStateRoot;
    }

    emit DesertBatchVerified(batchNumber, baseStoredBatch.batchNumber, endEvmBlockNumber, newBatchData.newEvmBlockhash);
  }

  function _computeCommitments(
    DesertBatchInfo calldata newBatchData,
    StoredBatchInfo calldata baseStoredBatch,
    uint64 batchNumber,
    bytes32 oldStateRoot,
    bytes32 currentCoreStateRoot,
    bytes32 currentValidiumRoot
  ) internal pure returns (bytes32 commitment, bytes32 storedBatchHash) {
    uint256 evmNumBlocks = uint256(newBatchData.doneToCoreWritesCount) + newBatchData.doneToEvmWritesCount + newBatchData.evmPriorityRequestCount;
    uint256 endEvmBlockNumber = baseStoredBatch.commitBatchInfo.endEvmBlockNumber + evmNumBlocks;

    /// @solidity memory-safe-assembly
    assembly {
      let fmp := mload(0x40)
      let baseCommitBatchInfo := add(baseStoredBatch, 0x20)

      calldatacopy(fmp, calldatasize(), 0x2e0) // zero oldStateRoot, CommitBatchInfo, and tail commitment slots

      // Compute `commitment`.
      mstore(fmp, oldStateRoot) // oldStateRoot
      mstore(add(fmp, 0x20), calldataload(newBatchData)) // newStateRoot
      // onChainOperationsHash (fmp + 0x40) stays zero: desert batches carry no Core on-chain operations
      mstore(add(fmp, 0x60), calldataload(add(baseCommitBatchInfo, 0x40))) // endBlockNumber
      calldatacopy(add(fmp, 0xa0), add(baseCommitBatchInfo, 0x80), 0x40) // startTimestamp, endTimestamp
      mstore(add(fmp, 0xe0), currentCoreStateRoot) // newCoreStateRoot
      mstore(add(fmp, 0x100), currentValidiumRoot) // newValidiumRoot
      mstore(add(fmp, 0x140), calldataload(add(baseCommitBatchInfo, 0x120))) // prefixPriorityRequestHash
      mstore(add(fmp, 0x160), endEvmBlockNumber) // endEvmBlockNumber
      mstore(add(fmp, 0x180), evmNumBlocks) // evmNumBlocks
      calldatacopy(add(fmp, 0x1a0), add(newBatchData, 0x20), 0x60) // oldEvmBlockhash, newEvmBlockhash, evmPriorityRequestCount
      mstore(add(fmp, 0x200), calldataload(add(newBatchData, 0x80))) // prefixEvmPriorityRequestHash
      mstore(add(fmp, 0x240), calldataload(add(newBatchData, 0xa0))) // doneToCoreWritesCount
      mstore(add(fmp, 0x280), calldataload(add(newBatchData, 0xc0))) // doneToEvmWritesCount
      mstore(add(fmp, 0x2a0), calldataload(add(newBatchData, 0xe0))) // evmL1CallsRoot
      commitment := keccak256(fmp, 0x2e0)

      // Compute `storedBatchHash`.
      mstore(fmp, batchNumber) // batchNumber
      mstore(add(fmp, 0x2c0), commitment) // commitment
      storedBatchHash := keccak256(fmp, 0x2e0)
    }
  }

  function _getStateRoot(StoredBatchInfo calldata batch) internal view returns (bytes32) {
    bytes32 updatedStateRoot = stateRootUpdates[batch.batchNumber];
    return updatedStateRoot == bytes32(0) ? batch.commitBatchInfo.newStateRoot : updatedStateRoot;
  }

  /// @dev Batch verification for the OpenVM `verifier` (`IOpenVmZkLighterVerifier`).
  function _verifyBatch(IOpenVmZkLighterVerifier _verifier, bytes32 commitment, bytes calldata proof) internal view returns (bool success) {
    if (address(_verifier) == address(0)) {
      revert ZkLighter_VerifierNotSet();
    }
    success = _verifier.verify(proof, commitment);
  }

  /// @notice Computes the stored batch hash of an incoming batch (from commitment)
  ///
  /// @dev This function uses the memory beyond the fmp as scratch space.
  /// @dev This function does not clean the upper bytes of sub-256 bit fields in
  /// `CommitBatchInfo`. The range checks are deferred to the zk proof.
  /// @dev This code will perform the equivalent of:
  ///   bytes32 commitment = keccak256(abi.encode(oldStateRoot, newBatchData, aggregatedBlobCommitment));
  ///   storedBatchHash = hashStoredBatchInfo(
  ///     StoredBatchInfo({batchNumber: batchNumber, commitBatchInfo: newBatchData, commitment: commitment})
  ///   );
  /// where `oldStateRoot` is `_getStateRoot(lastStoredBatch)`, i.e. the previous batch's
  /// `stateRootUpdates` entry if set, otherwise its `commitBatchInfo.newStateRoot`.
  ///
  /// @dev Note the following equivalences (`CommitBatchInfo` has only static fields, so it is
  /// ABI-encoded in place as 21 words):
  ///   - commitment == H(oldStateRoot + abi.encode(newBatchData) + aggregatedBlobCommitment)
  ///   - storedBatchHash == H(batchNumber + abi.encode(newBatchData) + commitment)
  ///
  /// We exploit the above for the following optimized sequence of memory operations:
  ///   - Compute the `commitment` by hashing:
  ///     - [fmp] oldStateRoot
  ///     - [fmp + 0x20..fmp + 0x2c0] newBatchData.newStateRoot..newBatchData.evmL1CallsRoot
  ///     - [fmp + 0x2c0] aggregatedBlobCommitment
  ///   - Compute the `storedBatchHash` by hashing:
  ///     - [fmp] batchNumber
  ///     - [fmp + 0x20..fmp + 0x2c0] newBatchData.newStateRoot..newBatchData.evmL1CallsRoot
  ///     - [fmp + 0x2c0] commitment
  function _computeStoredBatchHash(
    CommitBatchInfo calldata newBatchData,
    uint256 batchNumber,
    bytes32 oldStateRoot,
    bytes32 aggregatedBlobCommitment
  ) internal pure returns (bytes32 storedBatchHash) {
    uint256 tailCommitmentOffset = TAIL_COMMITMENT_OFFSET;
    /// @solidity memory-safe-assembly
    assembly {
      let fmp := mload(0x40)

      // Compute `commitment`
      mstore(fmp, oldStateRoot)
      calldatacopy(add(fmp, 0x20), newBatchData, COMMIT_BATCH_INFO_LENGTH)
      mstore(add(fmp, tailCommitmentOffset), aggregatedBlobCommitment)
      let commitment := keccak256(fmp, 0x2e0)

      // Compute `storedBatchHash`
      mstore(fmp, batchNumber)
      mstore(add(fmp, tailCommitmentOffset), commitment)

      storedBatchHash := keccak256(fmp, 0x2e0)
    }
  }

  /// @inheritdoc IZkLighter
  function appendBatchBlobs(
    StoredBatchInfo calldata batch,
    bytes32 previousAggregatedBlobCommitment,
    bytes32 oldStateRoot,
    bytes calldata pubdataCommitments
  ) external nonReentrant onlyActive {
    governance.isActiveValidator(msg.sender);

    if (batch.batchNumber <= verifiedBatchesCount) {
      revert ZkLighter_CannotAppendBlobsToVerifiedBatch();
    }
    if (pubdataCommitments.length == 0) {
      revert ZkLighter_InvalidBlobCommitmentParams();
    }

    bytes32 aggregatedBlobCommitment = _processBlobs(pubdataCommitments, previousAggregatedBlobCommitment);

    bytes32 currentStoredBatchHash = storedBatchHashes[batch.batchNumber];
    (bytes32 previousStoredBatchHash, bytes32 newStoredBatchHash) = _computeStoredBatchHashesForAppend({
      batch: batch,
      oldStateRoot: oldStateRoot,
      previousAggregatedBlobCommitment: previousAggregatedBlobCommitment,
      aggregatedBlobCommitment: aggregatedBlobCommitment
    });
    if (currentStoredBatchHash != previousStoredBatchHash) {
      revert ZkLighter_StoredBatchInfoMismatch();
    }

    storedBatchHashes[batch.batchNumber] = newStoredBatchHash;

    emit BatchBlobsAppend(batch.batchNumber, newStoredBatchHash);
  }

  /// @dev This function performs the equivalent of:
  /// ```solidity
  ///   bytes32 previousCommitment =
  ///     keccak256(abi.encodePacked(oldStateRoot, abi.encode(batch.commitBatchInfo), previousAggregatedBlobCommitment));
  ///   bytes32 newCommitment =
  ///     keccak256(abi.encodePacked(oldStateRoot, abi.encode(batch.commitBatchInfo), aggregatedBlobCommitment));
  ///
  ///   previousStoredBatchHash = keccak256(
  ///     abi.encode(
  ///       StoredBatchInfo({
  ///         batchNumber: batch.batchNumber,
  ///         commitBatchInfo: batch.commitBatchInfo,
  ///         commitment: previousCommitment
  ///       })
  ///     )
  ///   );
  ///
  ///   newStoredBatchHash = keccak256(
  ///     abi.encode(
  ///       StoredBatchInfo({
  ///         batchNumber: batch.batchNumber,
  ///         commitBatchInfo: batch.commitBatchInfo,
  ///         commitment: newCommitment
  ///       })
  ///     )
  ///   );
  /// ```
  function _computeStoredBatchHashesForAppend(
    StoredBatchInfo calldata batch,
    bytes32 oldStateRoot,
    bytes32 previousAggregatedBlobCommitment,
    bytes32 aggregatedBlobCommitment
  ) internal pure returns (bytes32 previousStoredBatchHash, bytes32 newStoredBatchHash) {
    uint256 tailCommitmentOffset = TAIL_COMMITMENT_OFFSET;
    /// @solidity memory-safe-assembly
    assembly {
      let fmp := mload(0x40)

      // Compute the previous commitment from the caller-supplied aggregate.
      mstore(fmp, oldStateRoot)
      calldatacopy(add(fmp, 0x20), add(batch, 0x20), COMMIT_BATCH_INFO_LENGTH)
      mstore(add(fmp, tailCommitmentOffset), previousAggregatedBlobCommitment)
      let previousCommitment := keccak256(fmp, 0x2e0)

      // Reuse the same preimage by swapping in the new aggregate blob
      // commitment.
      mstore(add(fmp, tailCommitmentOffset), aggregatedBlobCommitment)
      let newCommitment := keccak256(fmp, 0x2e0)

      // Authenticate the caller-supplied previous aggregate against the
      // currently stored batch hash.
      mstore(fmp, calldataload(batch))
      mstore(add(fmp, tailCommitmentOffset), previousCommitment)
      previousStoredBatchHash := keccak256(fmp, 0x2e0)

      mstore(add(fmp, tailCommitmentOffset), newCommitment)
      newStoredBatchHash := keccak256(fmp, 0x2e0)
    }
  }

  /// @inheritdoc IZkLighter
  function verifyBatch(StoredBatchInfo calldata batch, bytes calldata proof) external nonReentrant onlyActive {
    governance.isActiveValidator(msg.sender);

    if (batch.batchNumber != verifiedBatchesCount + 1) {
      revert ZkLighter_VerifyBatchNotInOrder();
    }
    if (hashStoredBatchInfo(batch) != storedBatchHashes[batch.batchNumber]) {
      revert ZkLighter_CannotVerifyNonCommittedBatch();
    }

    bool success = _verifyBatch(verifier, batch.commitment, proof);
    if (!success) {
      revert ZkLighter_VerifyBatchProofFailed();
    }

    _evmL1CallsRoots[batch.batchNumber] = batch.commitBatchInfo.evmL1CallsRoot;

    emit BatchVerification(
      batch.batchNumber,
      batch.commitBatchInfo.batchSize,
      batch.commitBatchInfo.endBlockNumber,
      batch.commitBatchInfo.endEvmBlockNumber,
      batch.commitBatchInfo.newEvmBlockhash
    );

    verifiedBatchesCount++;
    verifiedPriorityRequestCount += batch.commitBatchInfo.priorityRequestCount;
    verifiedEvmPriorityRequestCount += batch.commitBatchInfo.evmPriorityRequestCount;
    lastVerifiedStateRoot = batch.commitBatchInfo.newStateRoot;
    lastVerifiedCoreStateRoot = batch.commitBatchInfo.newCoreStateRoot;
    lastVerifiedValidiumRoot = batch.commitBatchInfo.newValidiumRoot;
    lastVerifiedEndBlockNumber = batch.commitBatchInfo.endBlockNumber;
    lastVerifiedEndEvmBlockNumber = batch.commitBatchInfo.endEvmBlockNumber;
    lastVerifiedEvmBlockhash = batch.commitBatchInfo.newEvmBlockhash;
    // Lazy update the executed batches count when:
    // 1. There are no pending items in onChainExecutionQueue and a new batch is verified
    // 2. The next batch in the onChainExecutionQueue is greater than the verifiedBatchesCount
    if (pendingOnChainBatchesCount == 0 || onChainExecutionQueue[executedOnChainBatchesCount].batchNumber > verifiedBatchesCount) {
      uint64 firstExecutedBatchNumber = executedBatchesCount + 1;
      executedBatchesCount = verifiedBatchesCount;
      stateRoot = batch.commitBatchInfo.newStateRoot;
      coreStateRoot = batch.commitBatchInfo.newCoreStateRoot;
      validiumRoot = batch.commitBatchInfo.newValidiumRoot;
      openPriorityRequestCount -= verifiedPriorityRequestCount - executedPriorityRequestCount;
      openEvmPriorityRequestCount -= verifiedEvmPriorityRequestCount - executedEvmPriorityRequestCount;
      executedPriorityRequestCount = verifiedPriorityRequestCount;
      executedEvmPriorityRequestCount = verifiedEvmPriorityRequestCount;
      emit BatchesExecuted(
        firstExecutedBatchNumber,
        executedBatchesCount,
        batch.commitBatchInfo.endBlockNumber,
        batch.commitBatchInfo.endEvmBlockNumber,
        batch.commitBatchInfo.newEvmBlockhash
      );
    }
  }

  function _executeOneBatch(bytes32 batchOnChainOperationsHash, bytes calldata _onChainOperationsPubData) internal {
    bytes32 onChainPubDataHash = bytes32(0);
    uint256 len = _onChainOperationsPubData.length;
    for (uint256 i = 0; i < len; ) {
      uint8 logType = Bytes.unsafeReadU8At(_onChainOperationsPubData, i);

      /// L1Call pubdata is serialized as
      /// `abi.encodePacked(TxTypes.OnChainPubDataType.L1Call,
      /// l1CallHash)` where
      ///  - `l1CallHash` is a 32-byte hash.
      if (logType == uint8(TxTypes.OnChainPubDataType.L1Call)) {
        if (len - i < TxTypes.L1CallLogSize) {
          revert ZkLighter_InvalidPubDataLength();
        }
        bytes32 l1CallHash = Bytes.unsafeReadBytes32At(_onChainOperationsPubData, i + 1);
        _persistL1CallHash(l1CallHash);
        onChainPubDataHash = keccak256(abi.encodePacked(onChainPubDataHash, TxTypes.OnChainPubDataType.L1Call, l1CallHash));
        i += 33; // 1 byte type + 32 bytes hash
      } else {
        revert ZkLighter_InvalidPubDataType();
      }
    }
    if (onChainPubDataHash != batchOnChainOperationsHash) {
      revert ZkLighter_OnChainOperationsHashMismatch();
    }
  }

  function _persistL1CallHash(bytes32 _l1CallHash) internal {
    if (_l1CallStatus[_l1CallHash] == L1CallStatus.Nonexistent) {
      _l1CallStatus[_l1CallHash] = L1CallStatus.Ready;
    }
  }

  function executeBatches(StoredBatchInfo[] calldata batches, bytes[] calldata onChainOperationsPubData) external nonReentrant onlyActive {
    if (batches.length != onChainOperationsPubData.length) {
      revert ZkLighter_ExecuteInputLengthMismatch();
    }
    if (batches.length > pendingOnChainBatchesCount) {
      revert ZkLighter_ExecuteInputLengthGreaterThanPendingCount();
    }
    uint64 firstExecutedBatchNumber = executedBatchesCount + 1;
    for (uint256 i = 0; i < batches.length; ++i) {
      uint64 batchNumber = batches[i].batchNumber;
      if (batchNumber > verifiedBatchesCount) {
        revert ZkLighter_CannotExecuteNonVerifiedBatch();
      }
      if (batchNumber != onChainExecutionQueue[executedOnChainBatchesCount].batchNumber) {
        revert ZkLighter_BatchNotInOnChainQueue();
      }
      if (storedBatchHashes[batchNumber] != hashStoredBatchInfo(batches[i])) {
        revert ZkLighter_StoredBatchInfoMismatch();
      }
      _executeOneBatch(batches[i].commitBatchInfo.onChainOperationsHash, onChainOperationsPubData[i]);

      uint64 numExecutedPriorityRequests = onChainExecutionQueue[executedOnChainBatchesCount].totalPriorityRequests - executedPriorityRequestCount;
      uint64 numExecutedEvmPriorityRequests = onChainExecutionQueue[executedOnChainBatchesCount].totalEvmPriorityRequests -
        executedEvmPriorityRequestCount;

      executedPriorityRequestCount = onChainExecutionQueue[executedOnChainBatchesCount].totalPriorityRequests;
      executedEvmPriorityRequestCount = onChainExecutionQueue[executedOnChainBatchesCount].totalEvmPriorityRequests;

      executedBatchesCount = batchNumber;
      executedOnChainBatchesCount++;
      pendingOnChainBatchesCount--;

      openPriorityRequestCount -= numExecutedPriorityRequests;
      openEvmPriorityRequestCount -= numExecutedEvmPriorityRequests;
    }
    stateRoot = batches[batches.length - 1].commitBatchInfo.newStateRoot;
    coreStateRoot = batches[batches.length - 1].commitBatchInfo.newCoreStateRoot;
    validiumRoot = batches[batches.length - 1].commitBatchInfo.newValidiumRoot;
    // Lazy update the executed batches count when:
    // 1. There are no pending items in onChainExecutionQueue and a new batch is verified
    // 2. The next batch in the onChainExecutionQueue is greater than the verifiedBatchesCount
    if (pendingOnChainBatchesCount == 0 || onChainExecutionQueue[executedOnChainBatchesCount].batchNumber > verifiedBatchesCount) {
      executedBatchesCount = verifiedBatchesCount;
      stateRoot = lastVerifiedStateRoot;
      coreStateRoot = lastVerifiedCoreStateRoot;
      validiumRoot = lastVerifiedValidiumRoot;

      openPriorityRequestCount -= verifiedPriorityRequestCount - executedPriorityRequestCount;
      openEvmPriorityRequestCount -= verifiedEvmPriorityRequestCount - executedEvmPriorityRequestCount;
      executedPriorityRequestCount = verifiedPriorityRequestCount;
      executedEvmPriorityRequestCount = verifiedEvmPriorityRequestCount;
      emit BatchesExecuted(
        firstExecutedBatchNumber,
        executedBatchesCount,
        lastVerifiedEndBlockNumber,
        lastVerifiedEndEvmBlockNumber,
        lastVerifiedEvmBlockhash
      );
    } else {
      emit BatchesExecuted(
        firstExecutedBatchNumber,
        executedBatchesCount,
        batches[batches.length - 1].commitBatchInfo.endBlockNumber,
        batches[batches.length - 1].commitBatchInfo.endEvmBlockNumber,
        batches[batches.length - 1].commitBatchInfo.newEvmBlockhash
      );
    }
  }

  /// @inheritdoc IZkLighter
  function revertBatches(StoredBatchInfo[] calldata _batchesToRevert, StoredBatchInfo calldata _remainingBatch) external nonReentrant {
    if (!desertMode) {
      governance.isActiveValidator(msg.sender);
    }

    for (uint256 i = 0; i < _batchesToRevert.length; ++i) {
      StoredBatchInfo calldata storedBatchInfo = _batchesToRevert[i];
      if (storedBatchInfo.batchNumber == 0) {
        revert ZkLighter_CannotRevertGenesisBatch();
      }
      if (storedBatchHashes[committedBatchesCount] != hashStoredBatchInfo(storedBatchInfo)) {
        revert ZkLighter_StoredBatchInfoMismatch();
      }
      if (storedBatchInfo.batchNumber != committedBatchesCount) {
        revert ZkLighter_StoredBatchInfoMismatch();
      }
      delete storedBatchHashes[storedBatchInfo.batchNumber];
      delete _evmL1CallsRoots[storedBatchInfo.batchNumber];
      delete toCoreLiveness[storedBatchInfo.batchNumber];
      delete toEvmLiveness[storedBatchInfo.batchNumber];
      if (storedBatchInfo.commitBatchInfo.onChainOperationsHash != bytes32(0)) {
        if (pendingOnChainBatchesCount == 0) {
          revert ZkLighter_CannotRevertExecutedBatch();
        }
        uint64 totalOnChainBatchesCount = executedOnChainBatchesCount + pendingOnChainBatchesCount;
        if (onChainExecutionQueue[totalOnChainBatchesCount - 1].batchNumber != storedBatchInfo.batchNumber) {
          revert ZkLighter_StoredBatchInfoMismatch();
        }
        // Remove the batch from the execution queue
        delete onChainExecutionQueue[totalOnChainBatchesCount - 1];
        pendingOnChainBatchesCount--;
      }
      committedBatchesCount--;
      committedPriorityRequestCount -= storedBatchInfo.commitBatchInfo.priorityRequestCount;
      committedEvmPriorityRequestCount -= storedBatchInfo.commitBatchInfo.evmPriorityRequestCount;
      if (storedBatchInfo.batchNumber <= verifiedBatchesCount) {
        verifiedBatchesCount--;
        verifiedPriorityRequestCount -= storedBatchInfo.commitBatchInfo.priorityRequestCount;
        verifiedEvmPriorityRequestCount -= storedBatchInfo.commitBatchInfo.evmPriorityRequestCount;
      }
    }

    // Can not revert executed batch or priority requests
    if (
      committedBatchesCount < executedBatchesCount ||
      committedPriorityRequestCount < executedPriorityRequestCount ||
      committedEvmPriorityRequestCount < executedEvmPriorityRequestCount
    ) {
      revert ZkLighter_CannotRevertExecutedBatch();
    }

    // Make sure the remaining batch is the last batch
    if (storedBatchHashes[committedBatchesCount] != hashStoredBatchInfo(_remainingBatch)) {
      revert ZkLighter_StoredBatchInfoMismatch();
    }
    // If we reverted verified batches, update the last verified variables for lazy update on executions
    if (_remainingBatch.batchNumber == verifiedBatchesCount) {
      lastVerifiedStateRoot = _remainingBatch.commitBatchInfo.newStateRoot;
      lastVerifiedCoreStateRoot = _remainingBatch.commitBatchInfo.newCoreStateRoot;
      lastVerifiedValidiumRoot = _remainingBatch.commitBatchInfo.newValidiumRoot;
      lastVerifiedEndBlockNumber = _remainingBatch.commitBatchInfo.endBlockNumber;
      lastVerifiedEndEvmBlockNumber = _remainingBatch.commitBatchInfo.endEvmBlockNumber;
      lastVerifiedEvmBlockhash = _remainingBatch.commitBatchInfo.newEvmBlockhash;
    }
    emit BatchesRevert(committedBatchesCount);
  }

  /// @inheritdoc IZkLighter
  function activateDesertMode() external nonReentrant returns (bool) {
    bool coreHasExpiredRequest = openPriorityRequestCount != 0 &&
      priorityRequests[executedPriorityRequestCount].expirationTimestamp != 0 &&
      block.timestamp >= priorityRequests[executedPriorityRequestCount].expirationTimestamp;
    bool evmHasExpiredRequest = openEvmPriorityRequestCount != 0 &&
      evmPriorityRequests[executedEvmPriorityRequestCount].expirationTimestamp != 0 &&
      block.timestamp >= evmPriorityRequests[executedEvmPriorityRequestCount].expirationTimestamp;
    bool trigger = coreHasExpiredRequest || evmHasExpiredRequest || _streamHasExpiredWrite(toCoreLiveness) || _streamHasExpiredWrite(toEvmLiveness);
    if (trigger) {
      if (!desertMode) {
        desertMode = true;
        emit DesertMode();
      }
      return true;
    } else {
      return false;
    }
  }

  function _streamHasExpiredWrite(mapping(uint64 => BatchStreamUpdate) storage s) internal view returns (bool) {
    BatchStreamUpdate storage head = s[executedBatchesCount];
    if (head.doneWritesTotalCount == head.initWritesTotalCount) {
      return false;
    }

    uint64 firstPending = head.doneWritesTotalCount + 1;
    uint64 lo = 1;
    uint64 hi = executedBatchesCount + 1;

    while (lo < hi) {
      uint64 mid = lo + (hi - lo) / 2;

      if (s[mid].initWritesTotalCount < firstPending) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }

    assert(s[lo].initWritesTotalCount >= firstPending);
    return block.timestamp >= s[lo].expirationTimestamp;
  }

  /// @inheritdoc IZkLighter
  function DEPRECATED_lastAccountIndex() external view returns (uint48) {
    return _DEPRECATED_lastAccountIndex;
  }

  /// @inheritdoc IZkLighter
  function addressToAccountIndex(address _address) external view returns (uint48) {
    return _addressToAccountIndex[_address];
  }

  /// @inheritdoc IZkLighter
  function evmL1CallsRoots(uint64 batchNumber) external view returns (bytes32) {
    return _evmL1CallsRoots[batchNumber];
  }

  /// @inheritdoc IZkLighter
  function l1CallStatus(bytes32 l1CallHash) external view returns (L1CallStatus) {
    return _l1CallStatus[l1CallHash];
  }

  /// @notice Delegates the call to the additional part of the main contract.
  /// @notice Should be only use to delegate the external calls as it passes the calldata
  /// @notice All functions delegated to additional contract should NOT be nonReentrant
  function delegateAdditional() internal {
    if (address(this) == zklighterImplementation) {
      revert ZkLighter_ImplCantDelegateToAddl();
    }

    address _target = additionalZkLighter;
    assembly {
      // The pointer to the free memory slot
      let ptr := mload(0x40)
      // Copy function signature and arguments from calldata at zero position into memory at pointer position
      calldatacopy(ptr, 0x0, calldatasize())
      // Delegatecall method of the implementation contract, returns 0 on error
      let result := delegatecall(gas(), _target, ptr, calldatasize(), 0x0, 0)
      // Get the size of the last return data
      let size := returndatasize()
      // Copy the size length of bytes from return data at zero position to pointer position
      returndatacopy(ptr, 0x0, size)

      // Depending on result value
      switch result
      case 0 {
        // End execution and revert state changes
        revert(ptr, size)
      }
      default {
        // Return data with length of size at pointers position
        return(ptr, size)
      }
    }
  }

  /// @dev Gated to `onlyCoreMessaging` (in AdditionalZkLighter) so `_sender`
  /// cannot be spoofed by arbitrary callers.
  function addPriorityRequestExt(
    address _sender,
    uint8 _pubdataType,
    bytes calldata _priorityRequest,
    bytes calldata _pubDataWithMetadata
  ) external payable {
    delegateAdditional();
  }

  function addEvmPriorityRequest(
    address to,
    uint256 value,
    uint256 depositAmount,
    uint256 gasLimit,
    bool isCreation,
    address refundAddress,
    bytes memory data
  ) external payable {
    delegateAdditional();
  }

  function nextEvmPriorityRequestId() external view returns (uint64) {
    return executedEvmPriorityRequestCount + openEvmPriorityRequestCount;
  }

  /// @dev Implemented directly (not delegated) so the function can be `view`.
  /// Reads the transient storage slot set by `fulfillCoreL1Call` / `fulfillEvmL1Call`
  /// in AdditionalZkLighter.
  function l2Sender() public view returns (address _l2Sender) {
    /// @solidity memory-safe-assembly
    assembly {
      _l2Sender := tload(0x00)
    }
  }

  function fulfillCoreL1Call(address l2Sender_, address target, uint256 value, uint256 msgNonce, bytes calldata data) external {
    delegateAdditional();
  }

  function fulfillEvmL1Call(
    uint64 batchNumber,
    bytes32[] calldata proof,
    uint256 isLeft,
    address l2Sender_,
    address target,
    uint256 value,
    uint256 msgNonce,
    bytes calldata data
  ) external {
    delegateAdditional();
  }

  function setGasParams(uint32 _maxGasLimit, uint112 _baseFeeOverhead, uint112 _baseFeeScalar) external {
    delegateAdditional();
  }

  function setBlobGasParams(uint112 _blobBaseFeeOverhead, uint112 _blobBaseFeeScalar) external {
    delegateAdditional();
  }

  function getGasParams() public view returns (uint32 _maxGasLimit, uint112 _baseFeeOverhead, uint112 _baseFeeScalar) {
    _maxGasLimit = maxGasLimit;
    _baseFeeOverhead = baseFeeOverhead;
    _baseFeeScalar = baseFeeScalar;
  }

  function getBlobGasParams() public view returns (uint112 _blobBaseFeeOverhead, uint112 _blobBaseFeeScalar) {
    _blobBaseFeeOverhead = blobBaseFeeOverhead;
    _blobBaseFeeScalar = blobBaseFeeScalar;
  }

  function computePriorityFee(uint256 gasLimit) public view returns (uint256) {
    return
      _computePriorityFee({
        gasLimit: gasLimit,
        priorityBaseFee: _computePriorityBaseFee({baseFee: block.basefee, overhead: baseFeeOverhead, scalar: baseFeeScalar}),
        priorityBlobByteFee: _computePriorityBlobByteFee({blobBaseFee: block.blobbasefee, overhead: blobBaseFeeOverhead, scalar: blobBaseFeeScalar})
      });
  }

  /// @notice Verifies if the sent blob commitment data is consistent with the blob itself
  ///
  /// @dev For each blob, this function must do three things:
  ///   1. Verify the point evaluation proof using the EIP-4844 precompile
  ///   2. Commit to the versioned hash and (x, y) pair from the evaluation
  ///   proof using `keccak256(abi.encodePacked(blobVersionedHash,
  ///   evaluationPointX, evaluationPointY))`
  ///   3. Aggregate the above commitment into the aggregated blob commitment
  ///
  /// @param pubDataCommitments is a list of: evaluationPointX (32 bytes) || evaluationPointY (32 bytes) || commitment (48 bytes) || proof (48 bytes)) = 160 bytes
  /// @return aggregatedBlobCommitment is the aggregated blob commitment for all blobs in the pubDataCommitments
  function _processBlobs(bytes calldata pubDataCommitments) internal view returns (bytes32) {
    return _processBlobs(pubDataCommitments, bytes32(0));
  }

  function _processBlobs(bytes calldata pubDataCommitments, bytes32 aggregatedBlobCommitment) internal view returns (bytes32) {
    if (pubDataCommitments.length % BLOB_DATA_COMMITMENT_BYTE_SIZE != 0) {
      revert ZkLighter_InvalidBlobCommitmentParams();
    }

    uint256 blobCount = pubDataCommitments.length / BLOB_DATA_COMMITMENT_BYTE_SIZE;
    if (blobCount > MAX_BLOB_COUNT_PER_TX) {
      revert ZkLighter_InvalidBlobCount(blobCount);
    }

    // We load the fmp once, and will use the space beyond it as scratch space.
    uint256 fmp;
    /// @solidity memory-safe-assembly
    assembly {
      fmp := mload(0x40)
    }

    // Each iteration, we lay out the following in memory:
    //   [fmp] blobVersionedHash (bytes32)
    //   [fmp + 0x20] evaluationPointX (bytes32)
    //   [fmp + 0x40] evaluationPointY (bytes32)
    //   [fmp + 0x60] commitment (48 bytes)
    //   [fmp + 0x90] proof (48 bytes)
    //
    // [fmp..fmp + 0x60] is the commitment preimage
    // [fmp + 0x20..fmp + 0xc0] is the EIP-4844 precompile calldata
    for (uint256 i = 0; i < blobCount; i++) {
      bytes calldata _blobDataCommitment = pubDataCommitments[i * BLOB_DATA_COMMITMENT_BYTE_SIZE:(1 + i) * BLOB_DATA_COMMITMENT_BYTE_SIZE];
      address precompileAddress = POINT_EVALUATION_PRECOMPILE_ADDRESS;

      /// @solidity memory-safe-assembly
      assembly {
        let blobVersionedHash := blobhash(i)

        if iszero(blobVersionedHash) {
          mstore(0x00, 0x1548f506) // ZkLighter_InvalidBlobCommitmentParams()
          revert(0x1c, 0x04)
        }

        mstore(fmp, blobVersionedHash)
        calldatacopy(add(0x20, fmp), _blobDataCommitment.offset, _blobDataCommitment.length)

        // Call point-evaluation precompile with:
        // blobVersionedHash (32 bytes) || evaluationPointCommitmentProof (160 bytes)
        let ok := staticcall(gas(), precompileAddress, fmp, add(BLOB_DATA_COMMITMENT_BYTE_SIZE, 0x20), 0x00, 0x40)

        // staticcall failed
        if iszero(ok) {
          mstore(0x00, 0xb18c473e) // ZkLighter_InvalidPointEvaluationParams()
          revert(0x1c, 0x04)
        }

        // pairing check failed
        // The precompile returns (uint256, uint256); we check the latter 32 bytes.
        let result := mload(0x20)
        if iszero(eq(result, BLS_MODULUS)) {
          mstore(0x00, 0xb18c473e) // ZkLighter_InvalidPointEvaluationParams()
          revert(0x1c, 0x04)
        }

        let currentBlobCommitment := keccak256(fmp, 0x60)

        switch aggregatedBlobCommitment
        case 0 {
          aggregatedBlobCommitment := currentBlobCommitment
        }
        default {
          mstore(0x00, aggregatedBlobCommitment)
          mstore(0x20, currentBlobCommitment)
          aggregatedBlobCommitment := keccak256(0x00, 0x40)
        }
      }
    }

    // Verify there are no extra blob hashes attached to the call. `blobhash` will return 0 bytes if no blob
    // hash is present at given index. Leaps are not allowed, so checking the first next index is sufficient.
    bytes32 emptyBlobVersionedHash;
    assembly {
      emptyBlobVersionedHash := blobhash(blobCount)
    }
    if (emptyBlobVersionedHash != bytes32(0)) {
      revert ZkLighter_InvalidBlobCommitmentParams();
    }

    return aggregatedBlobCommitment;
  }
}
