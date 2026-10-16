// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {ZkLighter} from "../ZkLighter.sol";
import {IDesertVerifier} from "../interfaces/IDesertVerifier.sol";
import {IGovernance} from "../interfaces/IGovernance.sol";
import {IOpenVmZkLighterVerifier} from "../interfaces/IOpenVmZkLighterVerifier.sol";

/// @dev ZkLighter carries no initializer, so a proxy cannot be constructed against it directly.
/// Deploy this subclass as the proxy's initial target; Proxy delegatecalls initialize() on
/// construction. Deployments that need to set anything initialize() does not take, coreMessaging
/// in particular, then upgradeTarget to the real ZkLighter and pass it through upgrade().
contract ZkLighterInit is ZkLighter {
  function initialize(bytes calldata initializationParameters) external initializer {
    if (address(this) == zklighterImplementation) revert ZkLighter_CannotBeInitialisedByImpl();

    __ReentrancyGuard_init();

    (
      address _governanceAddress,
      address _verifierAddress,
      address _additionalZkLighter,
      address _desertVerifier,
      bytes32 _genesisStateRoot,
      bytes32 _genesisCoreStateRoot,
      bytes32 _genesisValidiumRoot,
      bytes32 _genesisEvmBlockHash
    ) = abi.decode(initializationParameters, (address, address, address, address, bytes32, bytes32, bytes32, bytes32));

    if (!_hasCode(_governanceAddress) || !_hasCode(_verifierAddress) || !_hasCode(_additionalZkLighter) || !_hasCode(_desertVerifier)) {
      revert ZkLighter_InvalidInitializeParameters();
    }

    verifier = IOpenVmZkLighterVerifier(_verifierAddress);
    governance = IGovernance(_governanceAddress);
    additionalZkLighter = _additionalZkLighter;
    desertVerifier = IDesertVerifier(_desertVerifier);

    // `_genesisStateRoot` is the global rollup root; `_genesisCoreStateRoot` is its Core component.
    stateRoot = _genesisStateRoot;
    coreStateRoot = _genesisCoreStateRoot;
    lastVerifiedCoreStateRoot = _genesisCoreStateRoot;
    storedBatchHashes[0] = _computeGenesisBatchHash(_genesisStateRoot, _genesisCoreStateRoot, _genesisValidiumRoot, _genesisEvmBlockHash);

    _DEPRECATED_lastAccountIndex = 2; // First 3 accounts are reserved for system accounts
  }

  /// @dev Compute keccak256(abi.encode(0, CommitBatchInfo{...}, 0)) for the
  /// genesis stored batch. Layout of `abi.encode(StoredBatchInfo)`:
  ///
  ///   slot 0 (offset 0x00): batchNumber (uint64)
  ///   slot 1 (offset 0x20): newStateRoot              ← _genesisStateRoot (global root)
  ///   slot 2 (offset 0x40): onChainOperationsHash
  ///   slot 3 (offset 0x60): endBlockNumber
  ///   slot 4 (offset 0x80): batchSize
  ///   slot 5 (offset 0xa0): startTimestamp
  ///   slot 6 (offset 0xc0): endTimestamp
  ///   slot 7 (offset 0xe0): newCoreStateRoot          ← _genesisCoreStateRoot
  ///   slot 8 (offset 0x100): newValidiumRoot          ← _genesisValidiumRoot
  ///   slot 9 (offset 0x120): priorityRequestCount
  ///   slot 10 (offset 0x140): prefixPriorityRequestHash
  ///   slot 11 (offset 0x160): endEvmBlockNumber
  ///   slot 12 (offset 0x180): evmNumBlocks
  ///   slot 13 (offset 0x1a0): oldEvmBlockhash
  ///   slot 14 (offset 0x1c0): newEvmBlockhash         ← _genesisEvmBlockHash
  ///   slot 15 (offset 0x1e0): evmPriorityRequestCount
  ///   slot 16 (offset 0x200): prefixEvmPriorityRequestHash
  ///   slot 17 (offset 0x220): initToCoreWritesCount
  ///   slot 18 (offset 0x240): doneToCoreWritesCount
  ///   slot 19 (offset 0x260): initToEvmWritesCount
  ///   slot 20 (offset 0x280): doneToEvmWritesCount
  ///   slot 21 (offset 0x2a0): evmL1CallsRoot
  ///   slot 22 (offset 0x2c0): commitment (= 0 for genesis)
  ///
  /// Total = 23 slots × 32 = 736 bytes = 0x2e0. `codecopy` from `codesize()`
  /// fills with zero (reads past code return 0); we only need to overwrite
  /// the four non-zero fields.
  function _computeGenesisBatchHash(
    bytes32 _genesisStateRoot,
    bytes32 _genesisCoreStateRoot,
    bytes32 _genesisValidiumRoot,
    bytes32 _genesisEvmBlockHash
  ) internal pure returns (bytes32 genesisBatchHash) {
    /// @solidity memory-safe-assembly
    assembly {
      let fmp := mload(0x40)
      codecopy(fmp, codesize(), 0x2e0)
      mstore(add(fmp, 0x20), _genesisStateRoot)
      mstore(add(fmp, 0xe0), _genesisCoreStateRoot)
      mstore(add(fmp, 0x100), _genesisValidiumRoot)
      mstore(add(fmp, 0x1c0), _genesisEvmBlockHash)
      genesisBatchHash := keccak256(fmp, 0x2e0)
    }
  }
}
