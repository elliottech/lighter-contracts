// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/// @notice Stores L1 fee inputs made available to Lighter EVM contracts.
contract GasPriceOracle {
  address public constant GAS_PRICE_ADMIN = 0xDeaDDEaDDeAdDeAdDEAdDEaddeAddEAdDEAd0001;

  /// @custom:storage-location erc7201:lighter.storage.GasPriceOracleStorage
  struct GasPriceOracleStorage {
    uint256 blobBaseFee;
  }

  error GasPriceOracle_CallerNotAuthorized();

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.GasPriceOracleStorage")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant GasPriceOracleStorageLocation = 0x0cd057cd3e669c6b747a8c12b495b197bbe7c0d695a1a486f7cb1a7f0bf82c00;

  function _getGasPriceOracleStorage() private pure returns (GasPriceOracleStorage storage $) {
    assembly {
      $.slot := GasPriceOracleStorageLocation
    }
  }

  function blobBaseFee() external view returns (uint256) {
    return _getGasPriceOracleStorage().blobBaseFee;
  }

  function setBlobBaseFee(uint256 blobBaseFee_) external {
    if (msg.sender != GAS_PRICE_ADMIN) revert GasPriceOracle_CallerNotAuthorized();
    _getGasPriceOracleStorage().blobBaseFee = blobBaseFee_;
  }
}
