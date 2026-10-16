// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {L1CoreMessaging} from "../messaging/L1CoreMessaging.sol";
import {IGovernance} from "../interfaces/IGovernance.sol";
import {IL1InteropManager} from "../interfaces/IL1InteropManager.sol";
import {IZkLighter} from "../interfaces/IZkLighter.sol";

/// @dev L1CoreMessaging with an initializer for fresh deployments (e.g. devnet).
contract L1CoreMessagingInit is L1CoreMessaging {
  error L1CoreMessagingInit_InvalidSystemAddresses();

  constructor(IZkLighter _zkLighter, IL1InteropManager _interopManager) L1CoreMessaging(_zkLighter, _interopManager) {}

  function initialize(bytes calldata args) external initializer {
    (address initialTreasury, address initialInsuranceFundOperator, address governance) = abi.decode(args, (address, address, address));
    if (initialTreasury == address(0) || initialInsuranceFundOperator == address(0) || governance == address(0)) {
      revert L1CoreMessaging_ZeroAddress();
    }
    if (initialTreasury == initialInsuranceFundOperator) revert L1CoreMessagingInit_InvalidSystemAddresses();

    uint48 migrationLastAccountIndex = ZK_LIGHTER.DEPRECATED_lastAccountIndex();

    CoreMessagingStorage storage $ = _getCoreMessagingStorage();
    $.governance = IGovernance(governance);
    $.migrationLastAccountIndex = migrationLastAccountIndex;
    $.lastAccountIndex = migrationLastAccountIndex;

    if (_getAccountIndexFromAddress(initialTreasury) != NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AddressInUse();
    if (_getAccountIndexFromAddress(initialInsuranceFundOperator) != NIL_ACCOUNT_INDEX) revert L1CoreMessaging_AddressInUse();

    $.treasury = initialTreasury;
    $.insuranceFundOperator = initialInsuranceFundOperator;
  }
}
