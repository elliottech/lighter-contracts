// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IEvmToL1Messenger {
  receive() external payable;

  function burn() external;
  function initiateWithdrawal(address _target, bytes memory _data) external payable;
  function sendTokenInfo(address _target, bytes memory _data) external;
  function msgNonce() external view returns (uint256);
}
