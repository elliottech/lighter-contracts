// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IL1EscrowGateway} from "../../interfaces/IL1EscrowGateway.sol";
import {IL1ReplayableMessenger} from "../../interfaces/IL1ReplayableMessenger.sol";
import {IZkLighter} from "../../interfaces/IZkLighter.sol";
import {DefaultEscrowGatewayBase} from "../DefaultEscrowGatewayBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title DefaultL1EscrowGateway
/// @notice L1-side gateway for permissionless bridging of L1-native tokens to
/// EVM.
contract DefaultL1EscrowGateway is DefaultEscrowGatewayBase, IL1EscrowGateway {
  using SafeERC20 for IERC20;

  IZkLighter public immutable ZK_LIGHTER;
  IL1ReplayableMessenger public immutable L1_REPLAYABLE_MESSENGER;
  address public immutable L1_INTEROP_MANAGER;

  error DefaultL1EscrowGateway_AmountMismatch();

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
    return msg.sender == ZK_LIGHTER.l1CallProxy() && ZK_LIGHTER.l2Sender() == COUNTERPART_GATEWAY;
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

  function _lockTokens(address token, uint256 amount) internal override {
    IERC20 erc20 = IERC20(token);
    uint256 balanceBefore = erc20.balanceOf(address(this));
    erc20.safeTransferFrom(msg.sender, address(this), amount);
    if (erc20.balanceOf(address(this)) != balanceBefore + amount) revert DefaultL1EscrowGateway_AmountMismatch();

    erc20.forceApprove(address(ZK_LIGHTER), amount);
    ZK_LIGHTER.lockTokens(token, amount);
    erc20.forceApprove(address(ZK_LIGHTER), 0);
  }

  function _releaseTokens(address token, address to, uint256 amount) internal override {
    ZK_LIGHTER.releaseTokens(token, to, amount);
  }
}
