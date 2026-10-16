// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IEvmL1RefundClaimer {
  function claims(address l1Address, uint32 assetIndex) external view returns (uint256 baseAmount);
  function claimNonces(address l1Address, uint32 assetIndex) external view returns (uint64 claimNonce);
  function creditClaimFromCore(address l1Address, uint32 assetIndex, uint128 baseAmount) external;
  function receiveL1AccountRefund(address l1Address, uint32 assetIndex, uint128 baseAmount) external payable;
  function claimTo(uint32 assetIndex, uint64 claimNonce, address recipient) external;
}
