// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IL1MintGateway} from "../../interfaces/IL1MintGateway.sol";
import {IL1ReplayableMessenger} from "../../interfaces/IL1ReplayableMessenger.sol";
import {IZkLighter} from "../../interfaces/IZkLighter.sol";
import {DefaultMintGatewayBase} from "../DefaultMintGatewayBase.sol";

/// @title DefaultL1MintGateway
/// @notice L1-side gateway for permissionless bridging of wrapped tokens.
/// Acts as a beacon for all deployed wrapped token proxies.
contract DefaultL1MintGateway is DefaultMintGatewayBase, IL1MintGateway {
  IZkLighter public immutable ZK_LIGHTER;
  IL1ReplayableMessenger public immutable L1_REPLAYABLE_MESSENGER;
  address public immutable L1_INTEROP_MANAGER;

  constructor(
    address evmEscrowGateway,
    address l1InteropManager,
    IZkLighter zkLighter,
    IL1ReplayableMessenger l1ReplayableMessenger
  ) DefaultMintGatewayBase(evmEscrowGateway) {
    ZK_LIGHTER = zkLighter;
    L1_REPLAYABLE_MESSENGER = l1ReplayableMessenger;
    L1_INTEROP_MANAGER = l1InteropManager;
  }

  function initialize(bytes calldata data) external initializer {
    address tokenImplementation = abi.decode(data, (address));
    _initializeDefaultMintGatewayBase(tokenImplementation);
  }

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
