// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract KeccakTest {
  constructor() {}

  struct StoredBatchInfo {
    uint64 batchNumber;
    uint64 endBlockNumber;
    uint32 batchSize;
    uint64 timestamp;
    uint32 priorityRequestCount;
    bytes32 prefixPriorityRequestHash;
    bytes32 onChainOperationsHash;
    bytes32 stateRoot;
    bytes32 validiumRoot;
    bytes32 commitment;
    bytes32 blobHash;
  }

  function hashStoredBatchInfo(StoredBatchInfo memory _batch) public pure returns (bytes32) {
    return keccak256(abi.encode(_batch));
  }

  function keccakLegacy(address fromAddr, uint256 fromAmount, bytes32 messageHash) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(messageHash, fromAmount, fromAddr));
  }

  function keccak(address fromAddr, uint256 fromAmount, bytes32 messageHash) public pure returns (bytes32) {
    return keccak256(abi.encode(messageHash, fromAmount, fromAddr));
  }

  function hashIt(bytes calldata allMessages) public pure returns (bytes32) {
    return keccak256(abi.encode(allMessages));
  }

  function hashItDirect(bytes calldata allMessages) public pure returns (bytes32) {
    return keccak256(allMessages);
  }
}
