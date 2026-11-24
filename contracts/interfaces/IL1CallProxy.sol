// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IL1CallProxy {
  function ZK_LIGHTER() external view returns (address);

  function execute(address target, bytes calldata data) external payable;
}
