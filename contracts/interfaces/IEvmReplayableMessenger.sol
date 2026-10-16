// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IEvmReplayableMessenger {
  function relayMessage(address from, address to, uint256 _nonce, bytes memory message) external payable;
  function xDomainSender() external view returns (address sender);
}
