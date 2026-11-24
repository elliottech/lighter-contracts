// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IEscrowGateway} from "../../interfaces/IEscrowGateway.sol";
import {IL1ReplayableMessenger} from "../../interfaces/IL1ReplayableMessenger.sol";
import {IMintGateway} from "../../interfaces/IMintGateway.sol";
import {IZkLighter} from "../../interfaces/IZkLighter.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CctpOptions} from "./cctp/CctpTypes.sol";

/// @notice Manages L1 USDC escrow in ZkLighter, backing Core asset 3 and the EVM USDC wrapper.
/// @dev Deploy behind an upgradeable proxy and pair with EvmUsdcGateway's proxy.
contract L1UsdcGateway is Initializable, IEscrowGateway {
  using SafeERC20 for IERC20;

  uint256 private constant REENTRANCY_TSLOT = 0;

  address public immutable L1_USDC;
  IZkLighter public immutable ZK_LIGHTER;
  IL1ReplayableMessenger public immutable L1_REPLAYABLE_MESSENGER;
  address public immutable EVM_GATEWAY;
  address public immutable EVM_WRAPPER;
  address public immutable L1_INTEROP_MANAGER;

  event TokensSent(address indexed localToken, address indexed to, uint256 amount);
  event TokensUnlocked(address indexed localToken, address indexed to, uint256 amount);

  error L1UsdcGateway_InvalidConfiguration();
  error L1UsdcGateway_InvalidAmount();
  error L1UsdcGateway_AmountMismatch();
  error L1UsdcGateway_InvalidRecipient();
  error L1UsdcGateway_UnauthorizedUnlock();
  error L1UsdcGateway_ReentrantCall();

  constructor(
    address l1Usdc,
    IZkLighter zkLighter,
    IL1ReplayableMessenger l1ReplayableMessenger,
    address evmMintGateway,
    address evmWrapper,
    address l1InteropManager
  ) {
    _disableInitializers();
    if (
      l1Usdc == address(0) ||
      address(zkLighter) == address(0) ||
      address(l1ReplayableMessenger) == address(0) ||
      evmMintGateway == address(0) ||
      evmWrapper == address(0) ||
      l1InteropManager == address(0)
    ) revert L1UsdcGateway_InvalidConfiguration();
    if (IERC20Metadata(l1Usdc).decimals() != 6) revert L1UsdcGateway_InvalidConfiguration();
    L1_USDC = l1Usdc;
    ZK_LIGHTER = zkLighter;
    L1_REPLAYABLE_MESSENGER = l1ReplayableMessenger;
    EVM_GATEWAY = evmMintGateway;
    EVM_WRAPPER = evmWrapper;
    L1_INTEROP_MANAGER = l1InteropManager;
  }

  modifier nonReentrant() {
    bool locked;
    assembly {
      locked := tload(REENTRANCY_TSLOT)
    }
    if (locked) revert L1UsdcGateway_ReentrantCall();
    assembly {
      tstore(REENTRANCY_TSLOT, 1)
    }
    _;
    assembly {
      tstore(REENTRANCY_TSLOT, 0)
    }
  }

  function initialize(bytes calldata) external initializer {}

  function externalGateway() external view override returns (address) {
    return EVM_GATEWAY;
  }

  /// @notice Lock L1 USDC and request wUSDC delivery on EVM.
  /// @dev CctpOptions is reserved for post-CCTP routing and ignored pre-CCTP.
  function sendTokens(address to, uint256 amount, uint256 gasLimit, CctpOptions calldata) external payable nonReentrant {
    _send({to: to, amount: amount, refundAddress: msg.sender, gasLimit: gasLimit});
  }

  /// @notice Lock L1 USDC and request wUSDC delivery with an explicit refund recipient.
  /// @dev CctpOptions is reserved for post-CCTP routing and ignored pre-CCTP.
  function sendTokensCustomRefund(
    address to,
    uint256 amount,
    address refundAddress,
    uint256 gasLimit,
    CctpOptions calldata
  ) external payable nonReentrant {
    _send({to: to, amount: amount, refundAddress: refundAddress, gasLimit: gasLimit});
  }

  function unlock(address token, address to, uint256 amount) external override nonReentrant {
    assert(token == L1_USDC);
    if (amount == 0) revert L1UsdcGateway_InvalidAmount();
    if (to == address(0)) revert L1UsdcGateway_InvalidRecipient();
    bool isInteropManager = msg.sender == L1_INTEROP_MANAGER;
    bool isCounterpart = msg.sender == ZK_LIGHTER.l1CallProxy() && ZK_LIGHTER.l2Sender() == EVM_GATEWAY;
    if (!isInteropManager && !isCounterpart) revert L1UsdcGateway_UnauthorizedUnlock();

    ZK_LIGHTER.releaseTokens(L1_USDC, to, amount);
    emit TokensUnlocked(token, to, amount);
  }

  function _send(address to, uint256 amount, address refundAddress, uint256 gasLimit) private {
    if (amount == 0) revert L1UsdcGateway_InvalidAmount();
    if (to == address(0)) revert L1UsdcGateway_InvalidRecipient();

    IERC20 usdc = IERC20(L1_USDC);
    uint256 balanceBefore = usdc.balanceOf(address(this));
    usdc.safeTransferFrom(msg.sender, address(this), amount);
    if (usdc.balanceOf(address(this)) != balanceBefore + amount) revert L1UsdcGateway_AmountMismatch();
    usdc.forceApprove(address(ZK_LIGHTER), amount);
    ZK_LIGHTER.lockTokens(L1_USDC, amount);
    usdc.forceApprove(address(ZK_LIGHTER), 0);
    L1_REPLAYABLE_MESSENGER.sendMessage{value: msg.value}({
      target: EVM_GATEWAY,
      message: abi.encodeCall(IMintGateway.mint, (EVM_WRAPPER, to, amount, "")),
      gasLimit: gasLimit,
      value: 0,
      refundAddress: refundAddress
    });
    emit TokensSent(L1_USDC, to, amount);
  }
}
