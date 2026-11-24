// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../lib/TxTypes.sol";
import "../ZkLighter.sol";
import "../Storage.sol";
import "../Config.sol";

contract ZkLighterTest is ZkLighter {
  address private immutable zklighterImplementation;

  constructor() {
    zklighterImplementation = address(this);
  }

  /// @notice Same as fallback but called when calldata is empty
  receive() external payable {
    _fallback();
  }

  function _fallback() internal {
    require(address(this) != zklighterImplementation, "Can not dirctly call by zklighterImplementation");
    address _target = address(additionalZkLighter);
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

  /// @notice Will run when no functions matches call data
  fallback() external payable {
    _fallback();
  }

  function getOnChainExecution(uint64 requestId) external view returns (ExecutionQueueItem memory) {
    return onChainExecutionQueue[requestId];
  }

  function getPriorityRequest(uint64 priorityRequestId) external view returns (PriorityRequest memory) {
    return priorityRequests[priorityRequestId];
  }

  function setPriorityRequest(uint64 priorityRequestId, bytes32 prefixHash, uint64 expirationTimestamp) external {
    priorityRequests[priorityRequestId] = PriorityRequest({prefixHash: prefixHash, expirationTimestamp: expirationTimestamp});
  }

  function setExpirationBlockNumber(uint64 timestamp) external {
    priorityRequests[executedPriorityRequestCount].expirationTimestamp = timestamp;
  }

  function getPendingBalances(uint16 assetIndex, address account) public view returns (uint128 balanceToWithdraw, uint8 reserveValue) {
    uint48 accountIndex = getAccountIndexFromAddress(account);
    balanceToWithdraw = pendingAssetBalances[assetIndex][accountIndex].balanceToWithdraw;
    reserveValue = pendingAssetBalances[assetIndex][accountIndex].gasReserveValue;
  }

  function setGovernanceAddress(address newGovernance) external {
    governance = IGovernance(newGovernance);
  }

  function setAdditionalZkLighterAddress(address newAdditionalZkLighter) external {
    additionalZkLighter = AdditionalZkLighter(newAdditionalZkLighter);
  }

  function setVerifierAddress(address newVerifier) external {
    verifier = IZkLighterVerifier(newVerifier);
  }

  function setDesertVerifierAddress(address newDesertVerifier) external {
    desertVerifier = IDesertVerifier(newDesertVerifier);
  }

  function setStoredBatchHash(uint64 batchNumber, bytes32 batchHash) external {
    storedBatchHashes[batchNumber] = batchHash;
  }

  function setCommittedBatchesCount(uint64 count) external {
    committedBatchesCount = count;
  }

  function setOpenPriorityRequestCount(uint64 count) external {
    openPriorityRequestCount = count;
  }

  function setDesertMode(bool enabled) external {
    desertMode = enabled;
  }

  function setPendingBalance(uint16 assetIndex, uint48 accountIndex, uint128 balanceToWithdraw) external {
    pendingAssetBalances[assetIndex][accountIndex].balanceToWithdraw = balanceToWithdraw;
  }

  function setStateRoot(bytes32 newStateRoot) external {
    stateRoot = newStateRoot;
  }

  function setStateRootUpgradeVerifierAddress(address newVerifier) external {
    stateRootUpgradeVerifier = IZkLighterStateRootUpgradeVerifier(newVerifier);
  }

  function setDeprecatedPendingBalance(uint48 masterAccountIndex, uint128 balanceToWithdraw) external {
    DEPRECATED_pendingBalance[masterAccountIndex] = DEPRECATED_PendingBalance({balanceToWithdraw: balanceToWithdraw, gasReserveValue: 0});
  }

  function setCoreMessaging(address newCoreMessaging) external {
    coreMessaging = newCoreMessaging;
  }

  function setLastAccountIndex(uint48 newLastAccountIndex) external {
    lastAccountIndex = newLastAccountIndex;
  }

  function registerDefaultAssetConfigs() external {
    address ethAddress = address(0);
    uint56 ethExtensionMultiplier = 100;
    uint128 ethTickSize = 10 ** 10;
    assetConfigs[NATIVE_ASSET_INDEX] = AssetConfig({
      tokenAddress: ethAddress,
      withdrawalsEnabled: 1,
      extensionMultiplier: ethExtensionMultiplier,
      tickSize: ethTickSize,
      depositCapTicks: MAX_DEPOSIT_CAP_TICKS,
      minDepositTicks: 100_000
    });
    tokenToAssetIndex[ethAddress] = NATIVE_ASSET_INDEX;

    address usdcAddress = address(governance.usdc());
    uint56 usdcExtensionMultiplier = 1_000_000;
    uint128 usdcTickSize = 1;
    assetConfigs[USDC_ASSET_INDEX] = AssetConfig({
      tokenAddress: usdcAddress,
      withdrawalsEnabled: 1,
      extensionMultiplier: usdcExtensionMultiplier,
      tickSize: usdcTickSize,
      depositCapTicks: MAX_DEPOSIT_CAP_TICKS,
      minDepositTicks: 1_000_000
    });
    tokenToAssetIndex[usdcAddress] = USDC_ASSET_INDEX;
  }

  function setAddressToAccountIndex(address accountAddress, uint48 accountIndex) external {
    addressToAccountIndex[accountAddress] = accountIndex;
  }

  function depositTest(address _to, uint16 _assetIndex, TxTypes.RouteType _routeType, uint256 _amount) external payable {
    (bool success, bytes memory result) = address(additionalZkLighter).delegatecall(
      abi.encodeWithSignature("deposit(address,uint16,uint8,uint256)", _to, _assetIndex, uint8(_routeType), _amount)
    );
    if (!success) {
      assembly {
        revert(add(result, 0x20), mload(result))
      }
    }
  }

  function updateStateRootTest(StoredBatchInfo calldata _lastStoredBatch, bytes32 _stateRoot, bytes32 _validiumRoot, bytes calldata proof) external {
    (bool success, bytes memory result) = address(additionalZkLighter).delegatecall(
      abi.encodeCall(IZkLighter.updateStateRoot, (_lastStoredBatch, _stateRoot, _validiumRoot, proof))
    );
    if (!success) {
      assembly {
        revert(add(result, 0x20), mload(result))
      }
    }
  }

  function depositBatchTest(uint64[] calldata _amount, address[] calldata _to, uint48[] calldata _accountIndex) external {
    (bool success, bytes memory result) = address(additionalZkLighter).delegatecall(
      abi.encodeWithSignature("depositBatch(uint64[],address[],uint48[])", _amount, _to, _accountIndex)
    );
    if (!success) {
      assembly {
        revert(add(result, 0x20), mload(result))
      }
    }
  }

  function addPriorityRequestExt(
    address _sender,
    uint8 _pubdataType,
    bytes calldata _priorityRequest,
    bytes calldata _pubDataWithMetadata
  ) external override {
    (bool success, bytes memory result) = address(additionalZkLighter).delegatecall(msg.data);
    if (!success) {
      assembly {
        revert(add(result, 0x20), mload(result))
      }
    }
  }

  function getAssetConfig(uint16 assetIndex) external view returns (AssetConfig memory) {
    return assetConfigs[assetIndex];
  }
}
