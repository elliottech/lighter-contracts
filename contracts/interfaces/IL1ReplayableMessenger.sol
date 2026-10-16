// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IL1ReplayableMessenger {
  function sendMessage(address target, bytes calldata message, uint256 gasLimit, uint256 value, address refundAddress) external payable;

  function replayMessage(
    address _from,
    address _to,
    uint256 _value,
    uint256 _messageNonce,
    address _refundAddress,
    bytes memory _message,
    uint32 _newGasLimit
  ) external payable;
}
