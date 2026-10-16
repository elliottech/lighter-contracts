// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IL1EscrowGateway} from "../../interfaces/IL1EscrowGateway.sol";
import {IL1ReplayableMessenger} from "../../interfaces/IL1ReplayableMessenger.sol";
import {IZkLighter} from "../../interfaces/IZkLighter.sol";
import {DefaultEscrowGatewayBase} from "../DefaultEscrowGatewayBase.sol";

/// @title DefaultL1EscrowGateway
/// @notice L1-side gateway for permissionless bridging of L1-native tokens to
/// EVM.
contract DefaultL1EscrowGateway is DefaultEscrowGatewayBase, IL1EscrowGateway {
  IZkLighter public immutable ZK_LIGHTER;
  IL1ReplayableMessenger public immutable L1_REPLAYABLE_MESSENGER;
  address public immutable L1_INTEROP_MANAGER;

  constructor(
    IZkLighter zkLighter,
    IL1ReplayableMessenger l1ReplayableMessenger,
    address evmMintGateway,
    address l1InteropManager
  ) DefaultEscrowGatewayBase(evmMintGateway) {
    ZK_LIGHTER = zkLighter;
    L1_REPLAYABLE_MESSENGER = l1ReplayableMessenger;
    L1_INTEROP_MANAGER = l1InteropManager;
  }

  function initialize(bytes calldata) external {}

  function _interopManager() internal view override returns (address) {
    return L1_INTEROP_MANAGER;
  }

  function _isCounterpartSender() internal view override returns (bool) {
    return msg.sender == address(ZK_LIGHTER) && ZK_LIGHTER.l2Sender() == COUNTERPART_GATEWAY;
  }

  function sendTokens(address token, address to, uint256 amount, uint256 gasLimit) external payable override nonReentrant {
    _send({token: token, to: to, amount: amount, refundAddress: msg.sender, gasLimit: gasLimit});
  }

  function sendTokensCustomRefund(
    address token,
    address to,
    uint256 amount,
    address refundAddress,
    uint256 gasLimit
  ) external payable override nonReentrant {
    _send({token: token, to: to, amount: amount, refundAddress: refundAddress, gasLimit: gasLimit});
  }

  function _send(address token, address to, uint256 amount, address refundAddress, uint256 gasLimit) internal {
    bytes memory message = _sendToCounterpart(token, to, amount);

    L1_REPLAYABLE_MESSENGER.sendMessage{value: msg.value}({
      target: COUNTERPART_GATEWAY,
      message: message,
      gasLimit: gasLimit,
      value: 0,
      refundAddress: refundAddress
    });

    emit TokensSent(token, to, amount);
  }
}
