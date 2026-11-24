// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

enum TransferMode {
  Standard,
  Fast
}

struct CctpOptions {
  TransferMode mode;
  /// @dev Maximum destination-deducted fee, in six-decimal USDC base units.
  uint256 maxFee;
}
