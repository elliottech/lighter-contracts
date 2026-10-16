// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IEvmMintGateway} from "../../interfaces/IEvmMintGateway.sol";
import {IEvmReplayableMessenger} from "../../interfaces/IEvmReplayableMessenger.sol";
import {IEvmToL1Messenger} from "../../interfaces/IEvmToL1Messenger.sol";
import {DefaultMintGatewayBase} from "../DefaultMintGatewayBase.sol";

/// @title DefaultEvmMintGateway
/// @notice EVM-side gateway for permissionless bridging of wrapped tokens.
/// Acts as a beacon for all deployed wrapped token proxies.
contract DefaultEvmMintGateway is DefaultMintGatewayBase, IEvmMintGateway {
  IEvmReplayableMessenger public immutable EVM_REPLAYABLE_MESSENGER;
  IEvmToL1Messenger public immutable EVM_TO_L1_MESSENGER;
  address public immutable EVM_INTEROP_MANAGER;

  constructor(
    address l1EscrowGateway,
    address evmInteropManager,
    IEvmReplayableMessenger evmReplayableMessenger,
    IEvmToL1Messenger evmToL1Messenger
  ) DefaultMintGatewayBase(l1EscrowGateway) {
    EVM_REPLAYABLE_MESSENGER = evmReplayableMessenger;
    EVM_TO_L1_MESSENGER = evmToL1Messenger;
    EVM_INTEROP_MANAGER = evmInteropManager;
  }

  function initialize(address tokenImplementation) external initializer {
    _initializeDefaultMintGatewayBase(tokenImplementation);
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
