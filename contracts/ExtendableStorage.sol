// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./interfaces/IZkLighterStateRootUpgradeVerifier.sol";

/// @title zkLighter Extendable Storage Contract
/// @author zkLighter Team
contract ExtendableStorage {
  uint256[420] private __gap;

  /// @dev Stores new state root at the batch number if state root upgrade happened
  mapping(uint64 => bytes32) public stateRootUpdates;

  /// @dev Verifier contract, used for verifying state root upgrade proofs
  IZkLighterStateRootUpgradeVerifier internal stateRootUpgradeVerifier;

  /// @dev Stores if the desert mode was performed for the account index
  /// @dev Deprecated: use accountPerformedDesertForAsset instead
  mapping(uint48 => bool) internal DEPRECATED_accountPerformedDesert;

  struct PendingBalance {
    uint128 balanceToWithdraw;
    uint8 gasReserveValue;
  }

  struct AssetConfig {
    address tokenAddress; // Base layer token address
    uint8 withdrawalsEnabled; // 0 if disabled, 1 if enabled
    uint56 extensionMultiplier; // Internal asset extension multiplier
    uint128 tickSize; // Balance change unit before applying the extension multiplier
    uint64 depositCapTicks; // Max deposit cap in ticks
    uint64 minDepositTicks; // Min deposit in ticks
  }

  mapping(uint16 => AssetConfig) public assetConfigs; // id -> config
  mapping(address => uint16) public tokenToAssetIndex; // token -> id
  mapping(uint16 => mapping(uint48 => PendingBalance)) internal pendingAssetBalances;
  mapping(uint16 => mapping(uint48 => bool)) internal accountPerformedDesertForAsset;
}
