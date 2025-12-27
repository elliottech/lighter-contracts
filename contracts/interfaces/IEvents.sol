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
  event Deposit(uint48 toAccountIndex, address toAddress, uint128 amount);

  /// @notice Event emitted when user requests to change their api public key
  event ChangePubKey(uint48 accountIndex, uint8 apiKeyIndex, bytes pubKey);

  /// @notice Market created event
  event CreateMarket(TxTypes.CreateMarket params, uint8 sizeDecimals, uint8 priceDecimals, bytes32 symbol);

  /// @notice Market updated event
  event UpdateMarket(TxTypes.UpdateMarket params);

  /// @notice Event emitted when a cancel all orders request is created
  event CancelAllOrders(uint48 accountIndex);

  /// @notice Event emitted when a withdraw request is created
  event Withdraw(uint48 accountIndex, uint64 usdcAmount);

  /// @notice Event emitted when a new create order is created
  event CreateOrder(TxTypes.CreateOrder params);

  /// @notice Event emitted when a new burn shares is created
  event BurnShares(TxTypes.BurnShares params);

  /// @notice Event emitted when user funds are withdrawn from the zkLighter state but not from contract
  event WithdrawPending(address indexed owner, uint128 amount);

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
