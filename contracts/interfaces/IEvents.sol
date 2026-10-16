// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../lib/TxTypes.sol";

/// @title zkLighter Events Interface
/// @author zkLighter Team
interface IEvents {
  /// @notice Event emitted when a batch is committed
  /// @dev `batchNumber` is indexed so offchain services can look up a batch's end EVM block
  /// boundary by number. The boundary values come from the calldata authenticated against
  /// `storedBatchHashes`, so they carry the same trust as contract storage.
  event BatchCommit(uint64 indexed batchNumber, uint32 batchSize, uint64 endBlockNumber, uint256 endEvmBlockNumber, bytes32 endEvmBlockHash);

  /// @notice Event emitted when additional blobs are appended to a committed batch
  event BatchBlobsAppend(uint64 indexed batchNumber, bytes32 newStoredBatchHash);

  /// @notice Event emitted when a batch is verified
  /// @dev Carries the batch's end EVM block boundary (see `BatchCommit`). A verified-but-not-yet
  /// executed batch can still be reverted, recommitted, and reverified, so a batch number can
  /// accumulate several verification events; the newest one on the canonical L1 chain is the
  /// authoritative boundary record.
  event BatchVerification(uint64 indexed batchNumber, uint32 batchSize, uint64 endBlockNumber, uint256 endEvmBlockNumber, bytes32 endEvmBlockHash);

  /// @notice Event emitted when batches until given batch number are executed
  /// @dev `lastBatchNumber` is indexed so offchain services can look up the execution record
  /// for a batch number directly. `endEvmBlockHash` is the proof-bound EVM block hash of
  /// `lastBatchNumber`: the direct path reads it from the executed batch's calldata and the
  /// lazy path from `lastVerifiedEvmBlockhash` (executed catches up to verified, so the
  /// verified tip is the executed tip there).
  event BatchesExecuted(
    uint64 firstBatchNumber,
    uint64 indexed lastBatchNumber,
    uint64 endBlockNumber,
    uint256 endEvmBlockNumber,
    bytes32 endEvmBlockHash
  );

  /// @notice Event emitted when batches are reverted
  event BatchesRevert(uint64 newCommittedBatchesCount);

  /// @notice Event emitted when user funds are withdrawn from contract
  event WithdrawPending(address indexed owner, uint32 assetIndex, uint128 baseAmount);

  /// @notice New priority request event. Emitted when a request is placed into mapping
  event NewPriorityRequest(address sender, uint64 serialId, uint8 pubdataType, bytes pubData, uint64 expirationTimestamp);

  /// @notice Desert mode entered event
  event DesertMode();

  /// @notice The state root upgrade event
  event StateRootUpdate(uint64 batchNumber, bytes32 oldStateRoot, bytes32 newStateRoot);

  /// @notice Event emitted when a desert mode L1 call hash is persisted
  event DesertL1CallHashPersisted(bytes32 l1CallHash, address toAddress, uint32 assetIndex, uint128 baseAmount);

  /// @notice Event emitted when a batch is committed, verified, and executed atomically in
  /// @notice desert mode via `desertVerifyBatch`.
  /// @dev Desert verification advances all three batch counters without emitting the normal
  /// lifecycle events, so this event carries the same proof-bound EVM boundary
  /// (`endEvmBlockNumber` + `endEvmBlockHash`) and serves as the boundary record for the
  /// batch number in every lifecycle stage.
  event DesertBatchVerified(uint64 indexed batchNumber, uint64 baseBatchNumber, uint256 endEvmBlockNumber, bytes32 endEvmBlockHash);
}
