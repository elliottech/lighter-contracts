// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IEvmToL1Messenger} from "../../interfaces/IEvmToL1Messenger.sol";

contract EvmReplayableMessenger {
  address internal immutable L1_REPLAYABLE_MESSENGER;

  uint256 private constant XDOMAIN_SENDER_TSLOT = 0x00;

  uint160 internal constant OFFSET = uint160(0x1111000000000000000000000000000000001111);

  error EvmReplayableMessenger_OnlyOtherMessenger();
  error EvmReplayableMessenger_MessageAlreadyExecuted();
  error EvmReplayableMessenger_CannotExecuteToSelf();
  error EvmReplayableMessenger_InvalidFromAddress();
  error EvmReplayableMessenger_MessageExecutionFailed(bytes returndata);

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.EvmReplayableMessengerStorage")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant EvmReplayableMessengerStorageLocation = 0xfc36f686b9475704530f8525be14bd93f5848d0ebb0c6c8dc8c5a7ff58949300;

  struct EvmReplayableMessengerStorage {
    // Messages relayed from the L1 counterpart and executed here, by message hash
    mapping(bytes32 messageHash => bool) executedMessages;
  }

  function _getEvmReplayableMessengerStorage() private pure returns (EvmReplayableMessengerStorage storage $) {
    assembly {
      $.slot := EvmReplayableMessengerStorageLocation
    }
  }

  constructor(address l1ReplayableMessenger) {
    L1_REPLAYABLE_MESSENGER = l1ReplayableMessenger;
  }

  function relayMessage(address from, address to, uint256 _nonce, bytes memory message) external payable {
    uint256 value = msg.value;

    // This prevents reentry
    if (_undoL1ToL2Alias(msg.sender) != L1_REPLAYABLE_MESSENGER) revert EvmReplayableMessenger_OnlyOtherMessenger();

    bytes32 messageHash = keccak256(abi.encodePacked(from, to, value, _nonce, message));
    EvmReplayableMessengerStorage storage $ = _getEvmReplayableMessengerStorage();

    if (to == address(this)) revert EvmReplayableMessenger_CannotExecuteToSelf();
    if (from == address(0)) revert EvmReplayableMessenger_InvalidFromAddress(); // Should never really happen
    if ($.executedMessages[messageHash]) revert EvmReplayableMessenger_MessageAlreadyExecuted();

    $.executedMessages[messageHash] = true;

    assembly {
      tstore(XDOMAIN_SENDER_TSLOT, from)
    }

    (bool success, bytes memory returndata) = to.call{value: value}(message);

    assembly {
      tstore(XDOMAIN_SENDER_TSLOT, 0)
    }

    if (!success) revert EvmReplayableMessenger_MessageExecutionFailed(returndata);
  }

  function xDomainSender() external view returns (address sender) {
    assembly {
      sender := tload(XDOMAIN_SENDER_TSLOT)
    }
  }

  function _undoL1ToL2Alias(address sender) internal pure returns (address l1Address) {
    unchecked {
      l1Address = address(uint160(sender) - OFFSET);
    }
  }
}
