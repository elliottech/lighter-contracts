// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IEvmReplayableMessenger} from "../../interfaces/IEvmReplayableMessenger.sol";
import {IZkLighter} from "../../interfaces/IZkLighter.sol";

contract L1ReplayableMessenger {
  IZkLighter internal immutable ZK_LIGHTER;
  address internal immutable EVM_REPLAYABLE_MESSENGER;

  uint256 private constant _REENTRANCY_TSLOT = 0x00;

  error L1ReplayableMessenger_ReentrantCall();
  error L1ReplayableMessenger_MessageNotSent();
  error L1ReplayableMessenger_InsufficientMsgValue();

  modifier nonReentrant() {
    bool locked;
    assembly {
      locked := tload(_REENTRANCY_TSLOT)
    }
    if (locked) revert L1ReplayableMessenger_ReentrantCall();
    assembly {
      tstore(_REENTRANCY_TSLOT, 1)
    }
    _;
    assembly {
      tstore(_REENTRANCY_TSLOT, 0)
    }
  }

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.L1ReplayableMessengerStorage")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant L1ReplayableMessengerStorageLocation = 0xc433858e0d0afad0bc819d65ad118a4ee9873345776724e26cde69eb0680e700;

  struct L1ReplayableMessengerStorage {
    mapping(bytes32 messageHash => uint256) sentMessagesTimestamp;
  }

  function _getL1ReplayableMessengerStorage() private pure returns (L1ReplayableMessengerStorage storage $) {
    assembly {
      $.slot := L1ReplayableMessengerStorageLocation
    }
  }

  constructor(address evmReplayableMessenger, IZkLighter zkLighter) {
    EVM_REPLAYABLE_MESSENGER = evmReplayableMessenger;
    ZK_LIGHTER = zkLighter;
  }

  function initialize(bytes calldata) external {}

  function sendMessage(address target, bytes calldata message, uint256 gasLimit, uint256 value, address refundAddress) external payable nonReentrant {
    uint256 _nonce = ZK_LIGHTER.nextEvmPriorityRequestId();

    uint256 fee = ZK_LIGHTER.computePriorityFee(gasLimit);
    if (msg.value < fee + value) revert L1ReplayableMessenger_InsufficientMsgValue();

    {
      // Note that this does NOT commit to the gas limit.
      bytes32 messageHash = _computeMessageHash({msgSender: msg.sender, to: target, value: value, _nonce: _nonce, message: message});

      L1ReplayableMessengerStorage storage $ = _getL1ReplayableMessengerStorage();
      $.sentMessagesTimestamp[messageHash] = block.timestamp;
    }

    bytes memory wrappedMessage = abi.encodeCall(IEvmReplayableMessenger.relayMessage, (msg.sender, target, _nonce, message));

    ZK_LIGHTER.addEvmPriorityRequest{value: msg.value}({
      to: EVM_REPLAYABLE_MESSENGER,
      value: value,
      depositAmount: value,
      refundAddress: refundAddress,
      gasLimit: gasLimit,
      isCreation: false,
      data: wrappedMessage
    });
  }

  function replayMessage(
    address _from,
    address _to,
    uint256 _value,
    uint256 _messageNonce,
    address _refundAddress,
    bytes memory _message,
    uint32 _newGasLimit
  ) external payable nonReentrant {
    bytes32 messageHash = _computeMessageHash({msgSender: _from, to: _to, value: _value, _nonce: _messageNonce, message: _message});

    uint256 fee = ZK_LIGHTER.computePriorityFee(_newGasLimit);
    if (msg.value < fee) revert L1ReplayableMessenger_InsufficientMsgValue();

    L1ReplayableMessengerStorage storage $ = _getL1ReplayableMessengerStorage();
    if ($.sentMessagesTimestamp[messageHash] == 0) revert L1ReplayableMessenger_MessageNotSent();

    bytes memory wrappedMessage = abi.encodeCall(IEvmReplayableMessenger.relayMessage, (_from, _to, _messageNonce, _message));

    ZK_LIGHTER.addEvmPriorityRequest{value: msg.value}({
      to: EVM_REPLAYABLE_MESSENGER,
      value: _value,
      gasLimit: _newGasLimit,
      depositAmount: 0,
      refundAddress: _refundAddress,
      isCreation: false,
      data: wrappedMessage
    });
  }

  /// @dev Uses the memory beyond the fmp as scratch space.
  /// @dev Equivalent to `keccak256(abi.encodePacked(msgSender, to, value, _nonce, message))`
  function _computeMessageHash(
    address msgSender,
    address to,
    uint256 value,
    uint256 _nonce,
    bytes memory message
  ) internal pure returns (bytes32 out) {
    /// @solidity memory-safe-assembly
    assembly {
      let fmp := mload(0x40)
      mstore(fmp, shl(0x60, msgSender))
      mstore(add(fmp, 0x14), shl(0x60, to))
      mstore(add(fmp, 0x28), value)
      mstore(add(fmp, 0x48), _nonce)
      mcopy(add(fmp, 0x68), add(message, 0x20), mload(message))

      out := keccak256(fmp, add(mload(message), 0x68))
    }
  }
}
