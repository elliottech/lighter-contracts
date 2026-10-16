// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {LIGHTER_CORE_SYSTEM_ADDR} from "../Constants.sol";

/// @notice Predeploy for writing requests from LighterEVM to Lighter Core.
/// Only callable by the EvmToCoreEntrypoint.
contract EvmToCoreMessenger {
  error EvmToCoreMessenger_InvalidInitiator();
  error EvmToCoreMessenger_Unauthorized();

  /// @dev Stored at `EvmToCoreMessengerStorageLocation`.
  struct EvmToCoreMessengerStorage {
    uint64 reqId;
  }

  // Storage slot for `EvmToCoreMessengerStorage`.
  bytes32 private constant EvmToCoreMessengerStorageLocation = 0xfba1da29e9106ba0570fa8f64ac63219d3c5328963dfe2e9c00366de1ea2d000;

  function _getEvmToCoreMessengerStorage() private pure returns (EvmToCoreMessengerStorage storage $) {
    assembly {
      $.slot := EvmToCoreMessengerStorageLocation
    }
  }

  address public immutable EVM_TO_CORE_ENTRYPOINT;

  event WriteToCore(address indexed sender, uint64 indexed reqId, bytes writeRequest);

  constructor(address _evmToCoreEntrypoint) {
    EVM_TO_CORE_ENTRYPOINT = _evmToCoreEntrypoint;
  }

  function reqId() external view returns (uint64) {
    return _getEvmToCoreMessengerStorage().reqId;
  }

  function writeToCore(address sender, bytes memory writeRequest) external returns (uint64 _reqId) {
    if (tx.origin == LIGHTER_CORE_SYSTEM_ADDR) revert EvmToCoreMessenger_InvalidInitiator();
    if (msg.sender != EVM_TO_CORE_ENTRYPOINT) revert EvmToCoreMessenger_Unauthorized();

    EvmToCoreMessengerStorage storage $ = _getEvmToCoreMessengerStorage();

    _reqId = $.reqId;
    emit WriteToCore(sender, _reqId, writeRequest);
    $.reqId++;
  }
}
