// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Config} from "../Config.sol";
import {
  EVM_INTEROP_MANAGER_ADDR,
  READ_CORE,
  STOP_LOSS_ORDER,
  TAKE_PROFIT_LIMIT_ORDER,
  MAX_ORDER_TYPE,
  MAX_TIME_IN_FORCE,
  MAX_ORDER_EXPIRY,
  MIN_CLIENT_ORDER_INDEX,
  MAX_ORDER_INDEX
} from "../Constants.sol";
import {IEvmToCoreMessenger} from "../interfaces/IEvmToCoreMessenger.sol";
import {TxTypes} from "../lib/TxTypes.sol";

/// @notice User-facing entrypoint for EVM-to-Core writes.
/// Also provides EvmInteropManager-callable functions for deposit registration
/// and EVM token link finalization. Only caller of EvmToCoreMessenger.
contract EvmToCoreEntrypoint is Config {
  error EvmToCoreEntrypoint_CallerNotAuthorized();
  error EvmToCoreEntrypoint_InvalidAccountIndex();
  error EvmToCoreEntrypoint_InvalidApiKeyIndex();
  error EvmToCoreEntrypoint_InvalidPubKey();
  error EvmToCoreEntrypoint_InvalidRecipient();
  error EvmToCoreEntrypoint_InvalidAmount();
  error EvmToCoreEntrypoint_InvalidAssetIndex();
  error EvmToCoreEntrypoint_InvalidEvmToken();
  error EvmToCoreEntrypoint_InvalidCreateOrderParameters();
  error EvmToCoreEntrypoint_InvalidMarketIndex();
  error EvmToCoreEntrypoint_InvalidOrderIndex();
  error EvmToCoreEntrypoint_InvalidShareAmount();
  error EvmToCoreEntrypoint_L1AccountDoesNotExist();
  error EvmToCoreEntrypoint_ReentrantCall();

  IEvmToCoreMessenger public immutable EVM_TO_CORE_MESSENGER;

  constructor(IEvmToCoreMessenger _evmToCoreMessenger) {
    EVM_TO_CORE_MESSENGER = _evmToCoreMessenger;
  }

  /// @notice Extra gas burned on the first EVM-account send-to-Core deposit
  /// to each recipient address.
  uint256 internal constant FIRST_CORE_WRITE_GAS = 146_000;

  /// @custom:storage-location erc7201:lighter.storage.EvmToCoreEntrypoint
  struct EvmToCoreEntrypointStorage {
    mapping(address => bool) registered;
  }

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.EvmToCoreEntrypoint")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant EvmToCoreEntrypointStorageLocation = 0xb49f6e252d4f900888218502e6f8e421a90840a3d2dbd2a35980f44147651200;

  function _getEvmToCoreEntrypointStorage() private pure returns (EvmToCoreEntrypointStorage storage $) {
    assembly {
      $.slot := EvmToCoreEntrypointStorageLocation
    }
  }

  uint256 private constant _REENTRANCY_TSLOT = 0x00;

  modifier nonReentrant() {
    bool locked;
    assembly {
      locked := tload(_REENTRANCY_TSLOT)
    }
    if (locked) revert EvmToCoreEntrypoint_ReentrantCall();
    assembly {
      tstore(_REENTRANCY_TSLOT, 1)
    }
    _;
    assembly {
      tstore(_REENTRANCY_TSLOT, 0)
    }
  }

  modifier onlyEvmInteropManager() {
    if (msg.sender != EVM_INTEROP_MANAGER_ADDR) revert EvmToCoreEntrypoint_CallerNotAuthorized();
    _;
  }

  /// @notice Whether `account` has already paid the first send-to-Core
  /// surcharge for the EVM-account path.
  /// Frontends can read this to predict first-call gas for that path.
  function isRegistered(address account) external view returns (bool) {
    return _getEvmToCoreEntrypointStorage().registered[account];
  }

  /// @dev Burn the state-allocation surcharge the first time we see `account`
  /// on the EVM-account send-to-Core path.
  function _ensureRegistered(address account) private {
    EvmToCoreEntrypointStorage storage $ = _getEvmToCoreEntrypointStorage();
    if ($.registered[account]) return;
    $.registered[account] = true;
    _consumeGas(FIRST_CORE_WRITE_GAS);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                EVM-TO-CORE WRITE FUNCTIONS                 */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function changePubKey(uint48 accountIndex, uint8 apiKeyIndex, bytes calldata pubKey) external nonReentrant returns (uint64 reqId) {
    if (accountIndex > MAX_ACCOUNT_INDEX) revert EvmToCoreEntrypoint_InvalidAccountIndex();
    if (apiKeyIndex > MAX_API_KEY_INDEX) revert EvmToCoreEntrypoint_InvalidApiKeyIndex();
    if (pubKey.length != PUB_KEY_BYTES_SIZE) revert EvmToCoreEntrypoint_InvalidPubKey();

    for (uint256 i; i != PUB_KEY_BYTES_SIZE; i += 8) {
      if (_readU64LEAt(pubKey, i) >= GOLDILOCKS_MODULUS) revert EvmToCoreEntrypoint_InvalidPubKey();
    }

    bytes memory request = TxTypes.writeEvmChangePubKey(accountIndex, apiKeyIndex, pubKey);
    reqId = EVM_TO_CORE_MESSENGER.writeToCore(msg.sender, request);
  }

  function _readU64LEAt(bytes calldata data, uint256 offset) private pure returns (uint64 value) {
    uint256 word;
    assembly {
      word := shr(192, calldataload(add(data.offset, offset)))
    }

    word = ((word & 0xFF00FF00FF00FF00) >> 8) | ((word & 0x00FF00FF00FF00FF) << 8);
    word = ((word & 0xFFFF0000FFFF0000) >> 16) | ((word & 0x0000FFFF0000FFFF) << 16);
    word = (word >> 32) | (word << 32);
    value = uint64(word);
  }

  function createOrder(
    uint48 accountIndex,
    uint16 marketIndex,
    uint48 clientOrderIndex,
    uint8 orderType,
    uint8 timeInForce,
    uint64 orderExpiry,
    uint48 amount,
    uint32 price,
    bool isAsk,
    bool reduceOnly,
    uint32 triggerPrice
  ) external nonReentrant returns (uint64 reqId) {
    if (accountIndex > MAX_ACCOUNT_INDEX) revert EvmToCoreEntrypoint_InvalidAccountIndex();
    if (marketIndex > MAX_PERPS_MARKET_INDEX && (marketIndex < MIN_SPOT_MARKET_INDEX || marketIndex > MAX_SPOT_MARKET_INDEX)) {
      revert EvmToCoreEntrypoint_InvalidMarketIndex();
    }
    if (orderType > MAX_ORDER_TYPE || timeInForce > MAX_TIME_IN_FORCE || orderExpiry > MAX_ORDER_EXPIRY || price < MIN_ORDER_PRICE) {
      revert EvmToCoreEntrypoint_InvalidCreateOrderParameters();
    }
    bool isSpotMarket = marketIndex >= MIN_SPOT_MARKET_INDEX;
    if (
      (amount == 0 && !reduceOnly) ||
      (isSpotMarket && reduceOnly) ||
      (isSpotMarket && orderType >= STOP_LOSS_ORDER && orderType <= TAKE_PROFIT_LIMIT_ORDER)
    ) {
      revert EvmToCoreEntrypoint_InvalidCreateOrderParameters();
    }

    bytes memory request = TxTypes.writeEvmCreateOrder(
      accountIndex,
      marketIndex,
      clientOrderIndex,
      orderType,
      timeInForce,
      orderExpiry,
      amount,
      price,
      isAsk,
      reduceOnly,
      triggerPrice
    );
    reqId = EVM_TO_CORE_MESSENGER.writeToCore(msg.sender, request);
  }

  /// @param orderIndex Either a client order index or an order index, so it spans both ranges.
  function cancelOrder(uint48 accountIndex, uint64 orderIndex) external nonReentrant returns (uint64 reqId) {
    if (accountIndex > MAX_ACCOUNT_INDEX) revert EvmToCoreEntrypoint_InvalidAccountIndex();
    if (orderIndex < MIN_CLIENT_ORDER_INDEX || orderIndex > MAX_ORDER_INDEX) revert EvmToCoreEntrypoint_InvalidOrderIndex();

    bytes memory request = TxTypes.writeEvmCancelOrder(accountIndex, orderIndex);
    reqId = EVM_TO_CORE_MESSENGER.writeToCore(msg.sender, request);
  }

  function cancelAllOrders(uint48 accountIndex) external nonReentrant returns (uint64 reqId) {
    if (accountIndex > MAX_ACCOUNT_INDEX) revert EvmToCoreEntrypoint_InvalidAccountIndex();

    bytes memory request = TxTypes.writeEvmCancelAllOrders(accountIndex);
    reqId = EVM_TO_CORE_MESSENGER.writeToCore(msg.sender, request);
  }

  function burnShares(uint48 accountIndex, uint48 publicPoolIndex, uint64 shareAmount) external nonReentrant returns (uint64 reqId) {
    if (accountIndex > MAX_ACCOUNT_INDEX) revert EvmToCoreEntrypoint_InvalidAccountIndex();
    if (accountIndex == publicPoolIndex) revert EvmToCoreEntrypoint_InvalidAccountIndex();
    if (publicPoolIndex > MAX_ACCOUNT_INDEX || publicPoolIndex <= MAX_MASTER_ACCOUNT_INDEX) {
      revert EvmToCoreEntrypoint_InvalidAccountIndex();
    }
    if (shareAmount < MIN_POOL_SHARES_TO_MINT_OR_BURN || shareAmount > MAX_POOL_SHARES_TO_MINT_OR_BURN) {
      revert EvmToCoreEntrypoint_InvalidShareAmount();
    }

    bytes memory request = TxTypes.writeEvmBurnShares(accountIndex, publicPoolIndex, shareAmount);
    reqId = EVM_TO_CORE_MESSENGER.writeToCore(msg.sender, request);
  }

  function withdrawToL1Address(
    uint48 accountIndex,
    uint32 assetIndex,
    address l1Recipient,
    TxTypes.RouteType routeType,
    uint64 baseAmount
  ) external nonReentrant returns (uint64 reqId) {
    if (accountIndex > MAX_ACCOUNT_INDEX) revert EvmToCoreEntrypoint_InvalidAccountIndex();
    if (assetIndex < MIN_ASSET_INDEX || assetIndex > MAX_ASSET_INDEX) revert EvmToCoreEntrypoint_InvalidAssetIndex();
    if (l1Recipient == address(0)) revert EvmToCoreEntrypoint_InvalidRecipient();
    if (baseAmount == 0 || baseAmount > MAX_WITHDRAWAL_BASE_AMOUNT) revert EvmToCoreEntrypoint_InvalidAmount();

    bytes memory request = TxTypes.writeEvmWithdrawToL1Address(accountIndex, assetIndex, l1Recipient, routeType, baseAmount);
    reqId = EVM_TO_CORE_MESSENGER.writeToCore(msg.sender, request);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*              EVM INTEROP MANAGER-ONLY FUNCTIONS            */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice Registers a send-to-Core deposit. Called by EvmInteropManager
  /// after it handles the token transfer.
  function registerSendToCore(
    address sender,
    uint32 assetIndex,
    address to,
    bool isL1Account,
    TxTypes.RouteType routeType,
    uint64 baseAmount
  ) external onlyEvmInteropManager returns (uint64 reqId) {
    if (assetIndex < MIN_ASSET_INDEX || assetIndex > MAX_ASSET_INDEX) revert EvmToCoreEntrypoint_InvalidAssetIndex();
    if (isL1Account) _requireExistingL1AccountOnCore(to);
    else _ensureRegistered(to);

    bytes memory request = TxTypes.writeEvmSendToCore(assetIndex, to, isL1Account, routeType, baseAmount);
    reqId = EVM_TO_CORE_MESSENGER.writeToCore(sender, request);
  }

  /// @notice Registers a sendToEvm write after EvmInteropManager validates
  /// the asset and recipient.
  function registerSendToEvm(
    address sender,
    uint48 accountIndex,
    uint32 assetIndex,
    address evmRecipient,
    TxTypes.RouteType routeType,
    uint64 baseAmount
  ) external onlyEvmInteropManager returns (uint64 reqId) {
    if (accountIndex > MAX_ACCOUNT_INDEX) revert EvmToCoreEntrypoint_InvalidAccountIndex();
    if (assetIndex < MIN_ASSET_INDEX || assetIndex > MAX_ASSET_INDEX) revert EvmToCoreEntrypoint_InvalidAssetIndex();

    bytes memory request = TxTypes.writeEvmSendToEvm(accountIndex, assetIndex, evmRecipient, routeType, baseAmount);
    reqId = EVM_TO_CORE_MESSENGER.writeToCore(sender, request);
  }

  /// @notice Finalizes an EVM-native token link on Core. Called by
  /// EvmInteropManager during onLinkEvmNativeToken.
  /// @dev No state-growth surcharge is charged here: this path is initiated on
  /// L1, so spam is already bounded by L1 gas costs.
  function finalizeEvmLink(uint32 assetIndex, address evmToken) external onlyEvmInteropManager {
    if (assetIndex < MIN_ASSET_INDEX || assetIndex > MAX_ASSET_INDEX) revert EvmToCoreEntrypoint_InvalidAssetIndex();
    if (evmToken == address(0)) revert EvmToCoreEntrypoint_InvalidEvmToken();

    bytes memory request = TxTypes.writeEvmFinalizeEvmLink(assetIndex, evmToken);
    EVM_TO_CORE_MESSENGER.writeToCore(EVM_INTEROP_MANAGER_ADDR, request);
  }

  /// @dev Spin until at least `amount` gas has been consumed. Used to charge
  /// for state transition work outside the EVM that the EVM gas meter does not see.
  function _consumeGas(uint256 amount) private view {
    uint256 target = gasleft() - amount;
    while (gasleft() > target) {}
  }

  function _requireExistingL1AccountOnCore(address l1Address) private view {
    // This read reverts for a missing account
    (bool success, bytes memory data) = address(READ_CORE).staticcall(abi.encodePacked(bytes2(0x0008), l1Address));
    if (!success || data.length < 32) revert EvmToCoreEntrypoint_L1AccountDoesNotExist();
  }
}
