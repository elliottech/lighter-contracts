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

  function setDesertVerifierAddress(address newDesertVerifier) external {
    desertVerifier = IDesertVerifier(newDesertVerifier);
  }

  function setStateRoot(bytes32 newStateRoot) external {
    stateRoot = newStateRoot;
  }

  function registerDefaultAssetConfigs() external {
    _registerDefaultAssetConfigs();
  }

  function setAddressToAccountIndex(address accountAddress, uint48 accountIndex) external {
    addressToAccountIndex[accountAddress] = accountIndex;
  }

  function depositTest(address _to, uint16 _assetIndex, TxTypes.RouteType _routeType, uint256 _amount) external payable {
    (bool success, ) = address(additionalZkLighter).delegatecall(
      abi.encodeWithSignature("deposit(address,uint16,uint8,uint256)", _to, _assetIndex, uint8(_routeType), _amount)
    );
    require(success, "Delegatecall to deposit failed");
  }

  function withdrawTest(uint48 _accountIndex, uint16 _assetIndex, TxTypes.RouteType _routeType, uint64 _baseAmount) external {
    (bool success, ) = address(additionalZkLighter).delegatecall(
      abi.encodeWithSignature("withdraw(uint48,uint16,uint8,uint64)", _accountIndex, _assetIndex, uint8(_routeType), _baseAmount)
    );
    require(success, "Delegatecall to withdraw failed");
  }

  function getAssetConfig(uint16 assetIndex) external view returns (AssetConfig memory) {
    return assetConfigs[assetIndex];
  }
}
