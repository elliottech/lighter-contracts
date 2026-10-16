// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./interfaces/IZkLighterStateRootUpgradeVerifier.sol";
import "./interfaces/IOpenVmZkLighterVerifier.sol";
import {Storage} from "./Storage.sol";

/// @title zkLighter Extendable Storage Contract
/// @author zkLighter Team
contract ExtendableStorage {
  uint256[420] private __gap;

  /// @dev Stores new state root at the batch number if state root upgrade happened
  mapping(uint64 => bytes32) public stateRootUpdates;

  /// @dev Verifier contract, used for verifying state root upgrade proofs
  IZkLighterStateRootUpgradeVerifier internal stateRootUpgradeVerifier;

  /// @dev Stores if the desert mode was performed for the account index
  /// @dev Deprecated: use accountPerformedDesertForAsset instead
  mapping(uint48 => bool) internal DEPRECATED_accountPerformedDesert;

  struct PendingBalance {
    uint128 balanceToWithdraw;
    uint8 gasReserveValue;
  }

  struct AssetConfig {
    address tokenAddress; // Base layer token address
    uint8 withdrawalsEnabled; // 0 if disabled, 1 if enabled
    uint56 extensionMultiplier; // Internal asset extension multiplier
    uint128 tickSize; // Balance change unit before applying the extension multiplier
    uint64 depositCapTicks; // Max deposit cap in ticks
    uint64 minDepositTicks; // Min deposit in ticks
  }

  mapping(uint32 => AssetConfig) public assetConfigs; // id -> config
  mapping(address => uint32) public tokenToAssetIndex; // token -> id
  /// @dev Deprecated
  mapping(uint32 => mapping(uint48 => PendingBalance)) internal DEPRECATED_pendingAssetBalances;
  mapping(uint32 => mapping(uint48 => bool)) internal accountPerformedDesertForAsset;

  /// @dev Address of the L1CoreMessaging contract
  address coreMessaging;

  enum L1CallStatus {
    Nonexistent,
    Ready,
    Fulfilled
  }

  /// @dev Tracks status of L1 call hashes for executeCoreL1Call / executeEvmL1Call
  mapping(bytes32 => L1CallStatus) internal l1CallStatus;

  /// @dev Monotonically decreasing nonce for desert mode L1 call hashes.
  uint256 desertModeNonce;

  uint256 public lastVerifiedEndEvmBlockNumber;
  bytes32 public lastVerifiedEvmBlockhash;
  mapping(uint64 => Storage.PriorityRequest) internal evmPriorityRequests;
  uint64 public committedEvmPriorityRequestCount;
  uint64 public verifiedEvmPriorityRequestCount;
  uint64 public executedEvmPriorityRequestCount;
  uint64 public openEvmPriorityRequestCount;

  uint32 maxGasLimit;
  uint112 baseFeeOverhead;
  uint112 baseFeeScalar;
  uint112 blobBaseFeeOverhead;
  uint112 blobBaseFeeScalar;

  struct BatchStreamUpdate {
    uint64 expirationTimestamp;
    uint64 initWritesTotalCount;
    uint64 doneWritesTotalCount;
  }

  /// @dev Liveness state for EVM-to-Core writes pending Core fulfillment.
  mapping(uint64 batchNumber => BatchStreamUpdate) internal toCoreLiveness;

  /// @dev Liveness state for Core-to-EVM writes pending EVM fulfillment.
  mapping(uint64 batchNumber => BatchStreamUpdate) internal toEvmLiveness;

  /// @dev Latest executed Core state root.
  bytes32 public coreStateRoot;

  /// @dev Latest verified Core state root.
  bytes32 public lastVerifiedCoreStateRoot;

  /// @dev Verifier contract for desert-mode batch progression proofs
  /// (`desertVerifyBatch`). Separate from `verifier`
  /// (normal batches) and `desertVerifier` (desert exits).
  IOpenVmZkLighterVerifier internal desertBatchVerifier;

  /// @dev Cumulative EVM priority request count accepted after a desert-mode
  /// batch. Used to validate overlapping desert-mode proofs without relying on
  /// the normal-mode previous batch being the latest accepted batch.
  mapping(uint64 batchNumber => uint64 count) internal desertEvmPriorityRequestCount;

  /// @dev Number of desert-mode batches.
  uint64 desertModeBatchesCount;

  /// @dev EVM-originated L1-call Merkle roots persisted when batches verify.
  mapping(uint64 batchNumber => bytes32 root) internal _evmL1CallsRoots;
}
