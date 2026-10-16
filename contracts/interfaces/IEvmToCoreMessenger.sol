// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IEvmToCoreMessenger {
  function writeToCore(address sender, bytes memory writeRequest) external returns (uint64 _reqId);
}
