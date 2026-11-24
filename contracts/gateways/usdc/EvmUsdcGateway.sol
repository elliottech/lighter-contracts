// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IEscrowGateway} from "../../interfaces/IEscrowGateway.sol";
import {IMintGateway} from "../../interfaces/IMintGateway.sol";
import {IEvmReplayableMessenger} from "../../interfaces/IEvmReplayableMessenger.sol";
import {IEvmToL1Messenger} from "../../interfaces/IEvmToL1Messenger.sol";
import {TransparentProxy} from "../../proxy/TransparentProxy.sol";
import {UsdcWrapperBootstrap} from "./UsdcWrapperBootstrap.sol";
import {CctpOptions} from "./cctp/CctpTypes.sol";
import {LighterWrappedERC20V1} from "../../token/LighterWrappedERC20V1.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Pre-CCTP USDC wrapper gateway paired with an L1 USDC escrow.
/// @dev Gateway and wrapper use separate zero-admin TransparentProxy instances.
/// Wrapper upgrades are protocol-controlled; the gateway only holds mint/burn authority.
contract EvmUsdcGateway is Initializable, IMintGateway {
  using SafeERC20 for IERC20;

  uint256 private constant REENTRANCY_TSLOT = 0;

  address public immutable L1_USDC;
  address public immutable CORE_TOKEN_ADMIN;
  address public immutable WRAPPER_BOOTSTRAP;
  address public immutable L1_GATEWAY;
  address public immutable EVM_INTEROP_MANAGER;
  IEvmReplayableMessenger public immutable EVM_REPLAYABLE_MESSENGER;
  IEvmToL1Messenger public immutable EVM_TO_L1_MESSENGER;

  /// @custom:storage-location erc7201:lighter.storage.EvmUsdcGateway
  struct EvmUsdcGatewayStorage {
    address wrapper;
  }

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.EvmUsdcGateway")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant EvmUsdcGatewayStorageLocation = 0x642eede60cd0d909d363f588f396e731cc58575ce0e053edfaec0189451e2700;

  function _getEvmUsdcGatewayStorage() private pure returns (EvmUsdcGatewayStorage storage $) {
    assembly {
      $.slot := EvmUsdcGatewayStorageLocation
    }
  }

  event TokensMinted(address indexed localToken, address indexed to, uint256 amount);
  event TokensSent(address indexed localToken, address indexed to, uint256 amount);
  event WrapperDeployed(address indexed wrapper);

  error EvmUsdcGateway_InvalidConfiguration();
  error EvmUsdcGateway_UnsupportedToken();
  error EvmUsdcGateway_InvalidDecimals();
  error EvmUsdcGateway_InvalidAmount();
  error EvmUsdcGateway_InvalidRecipient();
  error EvmUsdcGateway_UnauthorizedReceive();
  error EvmUsdcGateway_UnauthorizedManagerBurn();
  error EvmUsdcGateway_ReentrantCall();

  constructor(
    address l1Usdc,
    address coreTokenAdmin,
    address wrapperBootstrap,
    address l1EscrowGateway,
    address evmInteropManager,
    IEvmReplayableMessenger evmReplayableMessenger,
    IEvmToL1Messenger evmToL1Messenger
  ) {
    _disableInitializers();
    if (
      l1Usdc == address(0) ||
      coreTokenAdmin == address(0) ||
      wrapperBootstrap.code.length == 0 ||
      l1EscrowGateway == address(0) ||
      evmInteropManager == address(0) ||
      address(evmReplayableMessenger) == address(0) ||
      address(evmToL1Messenger) == address(0)
    ) revert EvmUsdcGateway_InvalidConfiguration();
    L1_USDC = l1Usdc;
    CORE_TOKEN_ADMIN = coreTokenAdmin;
    WRAPPER_BOOTSTRAP = wrapperBootstrap;
    L1_GATEWAY = l1EscrowGateway;
    EVM_INTEROP_MANAGER = evmInteropManager;
    EVM_REPLAYABLE_MESSENGER = evmReplayableMessenger;
    EVM_TO_L1_MESSENGER = evmToL1Messenger;
  }

  modifier nonReentrant() {
    bool locked;
    assembly {
      locked := tload(REENTRANCY_TSLOT)
    }
    if (locked) revert EvmUsdcGateway_ReentrantCall();
    assembly {
      tstore(REENTRANCY_TSLOT, 1)
    }
    _;
    assembly {
      tstore(REENTRANCY_TSLOT, 0)
    }
  }

  /// @notice Atomically deploy and initialize the single wrapper after genesis.
  function initialize() external initializer {
    address token = address(
      new TransparentProxy{salt: bytes32(uint256(uint160(L1_USDC)))}(
        WRAPPER_BOOTSTRAP,
        abi.encodeCall(UsdcWrapperBootstrap.initialize, (CORE_TOKEN_ADMIN))
      )
    );
    _getEvmUsdcGatewayStorage().wrapper = token;

    emit WrapperDeployed(token);
  }

  function externalGateway() external view override returns (address) {
    return L1_GATEWAY;
  }

  /// @notice Return the wrapper deployed during initialization, preserved across gateway upgrades.
  function wrapper() public view returns (address) {
    return _getEvmUsdcGatewayStorage().wrapper;
  }

  /// @dev The wrapper already exists; this interface hook only verifies the selection.
  function checkOrDeployToken(bytes32 salt, string calldata, string calldata, uint8 decimals) external view override {
    if (msg.sender != EVM_INTEROP_MANAGER) revert EvmUsdcGateway_UnauthorizedReceive();
    if (salt != bytes32(uint256(uint160(L1_USDC)))) revert EvmUsdcGateway_UnsupportedToken();
    if (decimals != 6) revert EvmUsdcGateway_InvalidDecimals();
    if (wrapper().code.length == 0) revert EvmUsdcGateway_InvalidConfiguration();
  }

  /// @dev Mint only for Core payouts or authenticated deposits from the L1 USDC gateway.
  function mint(address token, address to, uint256 amount, bytes calldata) external override nonReentrant {
    assert(token == wrapper());
    if (token.code.length == 0) revert EvmUsdcGateway_InvalidConfiguration();
    if (amount == 0) revert EvmUsdcGateway_InvalidAmount();
    if (to == address(0)) revert EvmUsdcGateway_InvalidRecipient();

    bool isInteropManager = msg.sender == EVM_INTEROP_MANAGER;
    bool isCounterpart = msg.sender == address(EVM_REPLAYABLE_MESSENGER) && EVM_REPLAYABLE_MESSENGER.xDomainSender() == L1_GATEWAY;

    if (!isInteropManager && !isCounterpart) revert EvmUsdcGateway_UnauthorizedReceive();

    LighterWrappedERC20V1(token).externalMint(to, amount);

    emit TokensMinted(token, to, amount);
  }

  /// @dev EvmIM transfers the user's wrapper to this gateway before calling managerBurn.
  function managerBurn(address token, uint256 amount) external override nonReentrant {
    assert(token == wrapper());
    if (token.code.length == 0) revert EvmUsdcGateway_InvalidConfiguration();
    if (amount == 0) revert EvmUsdcGateway_InvalidAmount();
    if (msg.sender != EVM_INTEROP_MANAGER) revert EvmUsdcGateway_UnauthorizedManagerBurn();

    LighterWrappedERC20V1(token).externalBurn(amount);
  }

  /// @notice Burn wUSDC and request delivery of L1 USDC to the recipient.
  /// @dev CctpOptions is reserved for the CCTP cutover and ignored before migration.
  function sendTokens(address to, uint256 amount, CctpOptions calldata) external nonReentrant {
    address token = wrapper();

    if (token.code.length == 0) revert EvmUsdcGateway_InvalidConfiguration();
    if (amount == 0) revert EvmUsdcGateway_InvalidAmount();
    if (to == address(0)) revert EvmUsdcGateway_InvalidRecipient();

    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    LighterWrappedERC20V1(token).externalBurn(amount);
    EVM_TO_L1_MESSENGER.initiateWithdrawal(L1_GATEWAY, abi.encodeCall(IEscrowGateway.unlock, (L1_USDC, to, amount)));

    emit TokensSent(token, to, amount);
  }
}
