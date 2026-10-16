// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IZkLighter} from "./interfaces/IZkLighter.sol";
import "./interfaces/IZkLighterDesertMode.sol";
import "./interfaces/IOpenVmZkLighterVerifier.sol";
import "./interfaces/IDesertVerifier.sol";
import "./interfaces/IGovernance.sol";
import "./Config.sol";

/// @title zkLighter Storage Contract
/// @author zkLighter Team
/// @dev Fields prefixed with `DEPRECATED_` are no longer used. They are kept so that the storage layout
/// stays compatible with earlier deployments of this contract.
contract Storage is IZkLighterDesertMode, Config {
  // Public tree roots
  bytes32 public stateRoot;
  bytes32 public validiumRoot;

  struct PriorityRequest {
    bytes32 prefixHash;
    uint64 expirationTimestamp;
  }

  /// @dev Priority Request mapping
  /// @dev Requests are indexed by their receiving order
  mapping(uint256 => PriorityRequest) internal priorityRequests;

  /// @notice Priority operation struct
  /// @dev Contains request type and hashed pubData
  struct OnChainL2Request {
    bytes20 hashedPubData;
    uint64 priorityRequestOffset;
  }

  enum MarketStatus {
    NONE,
    ACTIVE
  }

  /// @dev Deprecated: L2 Request mapping for L2 transactions that needs to be executed in the base layer
  mapping(uint64 => OnChainL2Request) internal __DEPRECATED_onChainL2Requests;

  /// @dev Verifier contract, used for verifying batch execution proofs
  IOpenVmZkLighterVerifier internal verifier;

  /// @dev Desert verifier contract, used for verifying desert mode proofs
  IDesertVerifier internal desertVerifier;

  /// @dev Governance contract, stores the governor of the network
  IGovernance internal governance;

  /// @dev Additional zkLighter implementation contract (code size limitations)
  address internal additionalZkLighter;

  /// @dev Number of priority requests committed
  uint64 public committedPriorityRequestCount;
  /// @dev Number of priority requests committed and verified
  uint64 public verifiedPriorityRequestCount;
  /// @dev Number of priority requests committed, verified and executed
  uint64 public executedPriorityRequestCount;
  /// @dev Number of queued priority requests waiting to be executed
  uint64 public openPriorityRequestCount;

  /// @dev Number of batches committed
  uint64 public committedBatchesCount;
  /// @dev Number of batches committed and verified
  uint64 public verifiedBatchesCount;
  /// @dev Number of batches committed, verified and executed
  uint64 public executedBatchesCount;

  /// @dev Number of queued batches that have onChainOperations waiting to be executed
  uint64 public pendingOnChainBatchesCount;
  /// @dev Number of queued batches that have onChainOperations executed
  uint64 public executedOnChainBatchesCount;

  bytes32 public lastVerifiedStateRoot;
  bytes32 public lastVerifiedValidiumRoot;
  uint64 public lastVerifiedEndBlockNumber;

  struct StoredBatchInfo {
    uint64 batchNumber;
    IZkLighter.CommitBatchInfo commitBatchInfo;
    bytes32 commitment;
  }

  /// @dev Stores hashed StoredBatchInfo indexed by the batchNumber
  mapping(uint64 => bytes32) public storedBatchHashes;

  struct ExecutionQueueItem {
    uint64 batchNumber;
    uint64 totalPriorityRequests;
    uint64 totalEvmPriorityRequests;
  }

  /// @dev Stores if a batch needs to be executed, indexed by the pendingOnChainBatchesCount and
  /// @dev executedOnChainBatchesCount, value is the batchNumber
  mapping(uint64 => ExecutionQueueItem) internal onChainExecutionQueue;

  /// @dev Flag indicates that desert (exit hatch) mode is triggered
  /// @dev Once desert mode is triggered, it can not be reverted
  bool public override desertMode;

  /// @dev Deprecated: Added a new mapping(uint48 => bool) internal accountPerformedDesert;
  mapping(uint32 => bool) internal __DEPRECATED_performedDesert;

  uint8 internal constant FILLED_GAS_RESERVE_VALUE = 0xff; // Used for setting gas reserve value, so that the slot will not be emptied with 0 balance

  struct DEPRECATED_PendingBalance {
    uint128 balanceToWithdraw;
    uint8 gasReserveValue;
  }

  /// @notice Address that collects fees from listed markets
  address public treasury;
  /// @notice Address that operates the insurance fund
  address public insuranceFundOperator;
  /// @notice Index of the last registered account in the network including the system accounts
  uint48 internal _DEPRECATED_lastAccountIndex;
  /// @notice Account address to account id mapping, excluding the system accounts
  mapping(address => uint48) internal _addressToAccountIndex;

  /// @dev Base layer withdrawable USDC balances for each master account index
  /// @dev Deprecated
  mapping(uint48 => DEPRECATED_PendingBalance) internal DEPRECATED_pendingBalance;

  /// @dev Deprecated state root updates mapping, moved to ExtendableStorage
  mapping(uint64 => bytes32) public __DEPRECATED_stateRootUpdates;

  modifier onlyActive() {
    if (desertMode) {
      // Desert mode activated
      revert ZkLighter_DesertModeActive();
    }
    _;
  }

  function hashStoredBatchInfo(StoredBatchInfo calldata _batch) internal pure returns (bytes32 out) {
    /// @solidity memory-safe-assembly
    assembly {
      let fmp := mload(0x40)
      calldatacopy(fmp, _batch, 0x2e0)
      out := keccak256(fmp, 0x2e0)
    }
  }

  /// @dev Equivalent to
  /// ```solidity
  /// bytes memory paddedPubData = new bytes(MAX_PRIORITY_REQUEST_PUBDATA_SIZE);
  /// for (uint256 i = 0; i < _pubData.length; ++i) {
  ///   paddedPubData[i] = _pubData[i];
  /// }
  /// return keccak256(abi.encodePacked(_prevHash, paddedPubData));
  /// ```
  /// @dev Assumes `_pubData.length <= MAX_PRIORITY_REQUEST_PUBDATA_SIZE`.
  /// @dev Uses the memory beyond the fmp as scratch space (calldata overload).
  function _hashPubDataPrefixed(bytes32 _prevHash, bytes calldata _pubData) internal pure returns (bytes32 result) {
    /// @solidity memory-safe-assembly
    assembly {
      let fmp := mload(0x40)
      mstore(fmp, _prevHash)
      // Zero-ize the padded region via calldatacopy past end of calldata
      // h/t https://github.com/Vectorized/solady/blob/main/src/utils/LibZip.sol#L74
      calldatacopy(add(fmp, 0x20), calldatasize(), MAX_PRIORITY_REQUEST_PUBDATA_SIZE)
      calldatacopy(add(fmp, 0x20), _pubData.offset, _pubData.length)
      result := keccak256(fmp, add(MAX_PRIORITY_REQUEST_PUBDATA_SIZE, 0x20))
    }
  }

  /// @dev Uses the memory beyond the fmp as scratch space.
  /// @dev Equivalent to `keccak256(abi.encodePacked(_l2Sender, to, value, _nonce, data))`
  function _computeL1CallHash(address _l2Sender, address to, uint256 value, uint256 _nonce, bytes memory data) internal pure returns (bytes32 out) {
    /// @solidity memory-safe-assembly
    assembly {
      let fmp := mload(0x40)
      mstore(fmp, shl(0x60, _l2Sender))
      mstore(add(fmp, 0x14), shl(0x60, to))
      mstore(add(fmp, 0x28), value)
      mstore(add(fmp, 0x48), _nonce)
      mcopy(add(fmp, 0x68), add(data, 0x20), mload(data))
      out := keccak256(fmp, add(mload(data), 0x68))
    }
  }

  function _computePriorityFee(uint256 gasLimit, uint256 priorityBaseFee, uint256 priorityBlobByteFee) internal pure returns (uint256) {
    uint256 executionFee = gasLimit * priorityBaseFee;
    uint256 runtimePubdataBytes = gasLimit / EVM_PUBDATA_GAS_PER_BYTE;
    uint256 intrinsicSenderBytes = EVM_STATE_DIFF_ACCOUNT_INIT_SIZE + EVM_STATE_DIFF_BALANCE_SIZE + EVM_STATE_DIFF_NONCE_SIZE;
    return executionFee + (runtimePubdataBytes + intrinsicSenderBytes) * priorityBlobByteFee;
  }

  function _computePriorityBaseFee(uint256 baseFee, uint112 overhead, uint112 scalar) internal pure returns (uint256) {
    unchecked {
      return (baseFee * scalar) / WAD + overhead;
    }
  }

  function _computePriorityBlobByteFee(uint256 blobBaseFee, uint112 overhead, uint112 scalar) internal pure returns (uint256) {
    unchecked {
      return (blobBaseFee * scalar) / WAD + overhead;
    }
  }

  function getAccountIndexFromAddress(address _address) internal view returns (uint48) {
    uint48 _accountIndex = _addressToAccountIndex[_address];
    if (_accountIndex == 0) {
      if (_address == treasury) {
        return TREASURY_ACCOUNT_INDEX;
      } else if (_address == insuranceFundOperator) {
        return INSURANCE_FUND_OPERATOR_ACCOUNT_INDEX;
      }
      return NIL_ACCOUNT_INDEX;
    }
    return _accountIndex;
  }
}
