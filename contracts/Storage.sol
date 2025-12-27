// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./interfaces/IZkLighterDesertMode.sol";
import "./interfaces/IZkLighterVerifier.sol";
import "./interfaces/IDesertVerifier.sol";
import "./interfaces/IGovernance.sol";
import "./AdditionalZkLighter.sol";
import "./Config.sol";

/// @title zkLighter Storage Contract
/// @author zkLighter Team
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
  mapping(uint64 => PriorityRequest) internal priorityRequests;

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
  IZkLighterVerifier internal verifier;

  /// @dev Desert verifier contract, used for verifying desert mode proofs
  IDesertVerifier internal desertVerifier;

  /// @dev Governance contract, stores the governor of the network
  IGovernance internal governance;

  /// @dev Additional zkLighter implementation contract (code size limitations)
  AdditionalZkLighter internal additionalZkLighter;

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
    uint64 endBlockNumber;
    uint32 batchSize;
    uint64 startTimestamp;
    uint64 endTimestamp;
    uint32 priorityRequestCount;
    bytes32 prefixPriorityRequestHash;
    bytes32 onChainOperationsHash;
    bytes32 stateRoot;
    bytes32 validiumRoot;
    bytes32 commitment;
  }

  /// @dev Stores hashed StoredBatchInfo indexed by the batchNumber
  mapping(uint64 => bytes32) public storedBatchHashes;

  struct ExecutionQueueItem {
    uint64 batchNumber;
    uint64 totalPriorityRequests;
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
  struct PendingBalance {
    uint128 balanceToWithdraw;
    uint8 gasReserveValue;
  }

  /// @notice Address that collects fees from listed markets
  address public treasury;
  /// @notice Address that operates the insurance fund
  address public insuranceFundOperator;
  /// @notice Index of the last registered account in the network including the system accounts
  uint48 public lastAccountIndex;
  /// @notice Account address to account id mapping, excluding the system accounts
  mapping(address => uint48) public addressToAccountIndex;
  /// @dev Base layer withdrawable USDC balances for each master account index
  mapping(uint48 => PendingBalance) internal pendingBalance;

  /// @dev Deprecated state root updates mapping, moved to ExtendableStorage
  mapping(uint64 => bytes32) public __DEPRECATED_stateRootUpdates;

  /// @notice Checks that current state not is desert mode
  modifier onlyActive() {
    if (desertMode) {
      // Desert mode activated
      revert ZkLighter_DesertModeActive();
    }
    _;
  }

  function hashStoredBatchInfo(StoredBatchInfo memory _batch) internal pure returns (bytes32) {
    return keccak256(abi.encode(_batch));
  }

  function getAccountIndexFromAddress(address _address) internal view returns (uint48) {
    uint48 _accountIndex = addressToAccountIndex[_address];
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
