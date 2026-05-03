// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../lib/TxTypes.sol";

/// @title zkLighter Events Interface
/// @author zkLighter Team
interface IEvents {
  /// @notice Event emitted when a batch is committed
  event BatchCommit(uint64 batchNumber, uint32 batchSize, uint64 endBlockNumber);

  /// @notice Event emitted when a batch is verified
  event BatchVerification(uint64 batchNumber, uint32 batchSize, uint64 endBlockNumber);

  /// @notice Event emitted when batches until given batch number are executed
  event BatchesExecuted(uint64 batchNumber, uint64 endBlockNumber);

  /// @notice Event emitted when batches are reverted
  event BatchesRevert(uint64 newTotalBlocksCommitted);

  /// @notice Event emitted when user funds are deposited to a zkLighter account
  event Deposit(uint48 toAccountIndex, address toAddress, uint16 assetIndex, TxTypes.RouteType routeType, uint128 baseAmount);

  /// @notice Market created event
  event CreateMarket(TxTypes.CreateMarket params, uint8 sizeDecimals, uint8 priceDecimals, bytes32 symbol);

  /// @notice Asset config registered event
  event RegisterAssetConfig(
    uint16 assetIndex,
    address tokenAddress,
    uint8 withdrawalsEnabled,
    uint56 extensionMultiplier,
    uint128 tickSize,
    uint64 depositCapTicks,
    uint64 minDepositTicks
  );

  /// @notice Asset config updated event
  event UpdateAssetConfig(uint16 assetIndex, uint8 withdrawalsEnabled, uint64 depositCapTicks, uint64 minDepositTicks);

  /// @notice Market updated event
  event UpdateMarket(TxTypes.UpdateMarket params);

  /// @notice Event emitted when user funds are withdrawn from contract
  event WithdrawPending(address indexed owner, uint16 assetIndex, uint128 baseAmount);

  /// @notice New priority request event. Emitted when a request is placed into mapping
  event NewPriorityRequest(address sender, uint64 serialId, uint8 pubdataType, bytes pubData, uint64 expirationTimestamp);

  /// @notice Desert mode entered event
  event DesertMode();

  /// @notice The treasury address changed
  event TreasuryUpdate(address newTreasury);

  /// @notice The insurance fund operator address changed
  event InsuranceFundOperatorUpdate(address newInsuranceFundOperator);

  /// @notice The state root upgrade event
  event StateRootUpdate(uint64 batchNumber, bytes32 oldStateRoot, bytes32 newStateRoot);
}
