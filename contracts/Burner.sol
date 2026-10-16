// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title Burner
/// @notice Burns any ETH sent to it by self-destructing in its constructor.
/// @notice Vendored unchanged (apart from the pragma) from Optimism's Burn.sol
///         (https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts-bedrock/src/libraries/Burn.sol).
///         See THIRD_PARTY_NOTICES.md.
contract Burner {
  constructor() payable {
    selfdestruct(payable(address(this)));
  }
}
