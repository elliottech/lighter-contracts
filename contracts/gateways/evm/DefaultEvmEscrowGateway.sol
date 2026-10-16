// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IEvmEscrowGateway} from "../../interfaces/IEvmEscrowGateway.sol";
import {IEvmReplayableMessenger} from "../../interfaces/IEvmReplayableMessenger.sol";
import {IEvmToL1Messenger} from "../../interfaces/IEvmToL1Messenger.sol";
import {DefaultEscrowGatewayBase} from "../DefaultEscrowGatewayBase.sol";

/// @title DefaultEvmEscrowGateway
/// @notice EVM-side gateway for permissionless bridging of EVM-native tokens to L1.
contract DefaultEvmEscrowGateway is DefaultEscrowGatewayBase, IEvmEscrowGateway {
  IEvmToL1Messenger public immutable EVM_TO_L1_MESSENGER;
  IEvmReplayableMessenger public immutable EVM_REPLAYABLE_MESSENGER;
  address public immutable EVM_INTEROP_MANAGER;

  constructor(
    IEvmToL1Messenger evmToL1Messenger,
    IEvmReplayableMessenger evmReplayableMessenger,
    address l1MintGateway,
    address evmInteropManager
  ) DefaultEscrowGatewayBase(l1MintGateway) {
    EVM_TO_L1_MESSENGER = evmToL1Messenger;
    EVM_REPLAYABLE_MESSENGER = evmReplayableMessenger;
    EVM_INTEROP_MANAGER = evmInteropManager;
  }

  function _interopManager() internal view override returns (address) {
    return EVM_INTEROP_MANAGER;
  }

  function _isCounterpartSender() internal view override returns (bool) {
    return msg.sender == address(EVM_REPLAYABLE_MESSENGER) && EVM_REPLAYABLE_MESSENGER.xDomainSender() == COUNTERPART_GATEWAY;
  }

  function sendTokens(address token, address to, uint256 amount) external override nonReentrant {
    bytes memory message = _sendToCounterpart(token, to, amount);
    EVM_TO_L1_MESSENGER.initiateWithdrawal({_target: COUNTERPART_GATEWAY, _data: message});
    emit TokensSent(token, to, amount);
  }
}
