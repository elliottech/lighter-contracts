// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IEscrowGateway} from "../interfaces/IEscrowGateway.sol";
import {IMintGateway} from "../interfaces/IMintGateway.sol";
import {TokenInteropLib} from "../interop/TokenInteropLib.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/// @title DefaultEscrowGatewayBase
/// @notice Shared logic for L1-native / EVM-native escrow gateways that lock
/// canonical tokens and bridge them to a counterpart mint gateway.
abstract contract DefaultEscrowGatewayBase is Initializable, IEscrowGateway {
  using SafeERC20 for IERC20;

  /// @custom:storage-location erc7201:lighter.storage.EscrowGateway
  struct EscrowGatewayStorage {
    mapping(address localToken => address) localToExternalToken;
  }

  address public immutable COUNTERPART_GATEWAY;
  bytes32 public immutable EXTERNAL_TOKEN_INIT_CODE_HASH;

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.EscrowGateway")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant EscrowGatewayStorageLocation = 0xb3a885f198226bedba8ae5fdc9caf04542cd922c1b6741c1ca23d79f9fec6500;

  function _getEscrowGatewayStorage() private pure returns (EscrowGatewayStorage storage $) {
    assembly {
      $.slot := EscrowGatewayStorageLocation
    }
  }

  uint256 private constant _REENTRANCY_TSLOT = 0x00;

  event TokensSent(address indexed localToken, address indexed to, uint256 amount);
  event TokensUnlocked(address indexed localToken, address indexed to, uint256 amount);

  error DefaultEscrowGatewayBase_UnauthorizedUnlock();
  error DefaultEscrowGatewayBase_InvalidRecipient();
  error DefaultEscrowGatewayBase_ReentrantCall();

  modifier nonReentrant() {
    bool locked;
    assembly {
      locked := tload(_REENTRANCY_TSLOT)
    }
    if (locked) revert DefaultEscrowGatewayBase_ReentrantCall();
    assembly {
      tstore(_REENTRANCY_TSLOT, 1)
    }
    _;
    assembly {
      tstore(_REENTRANCY_TSLOT, 0)
    }
  }

  constructor(address counterpartGateway) {
    _disableInitializers();
    COUNTERPART_GATEWAY = counterpartGateway;
    EXTERNAL_TOKEN_INIT_CODE_HASH = keccak256(abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(counterpartGateway, "")));
  }

  /// @dev Returns the local interop manager address used for auth.
  function _interopManager() internal view virtual returns (address);

  /// @dev Returns true when `msg.sender` is the cross-chain messenger relaying
  /// a call from the counterpart mint gateway.
  function _isCounterpartSender() internal view virtual returns (bool);

  /// @inheritdoc IEscrowGateway
  function externalGateway() external view override returns (address) {
    return COUNTERPART_GATEWAY;
  }

  /// @inheritdoc IEscrowGateway
  /// @dev Two callers are authorized:
  ///   1. The local interop manager — for Core withdrawals of native tokens.
  ///   2. The counterpart mint gateway (via messenger) — for cross-chain gateway transfers.
  /// The external token mapping is only populated when called by the counterpart
  /// gateway (case 2), since that's the only path where the remote token is
  /// guaranteed to exist.
  function unlock(address localToken, address to, uint256 amount) external override nonReentrant {
    bool isCounterpart = _isCounterpartSender();
    bool isInteropManager = msg.sender == _interopManager();
    if (!isCounterpart && !isInteropManager) revert DefaultEscrowGatewayBase_UnauthorizedUnlock();

    // If the message is from the counterpart, it means the counterpart no
    // longer needs metadata. We can populate the mapping for future calls
    // and stop sending metadata.
    if (isCounterpart) {
      EscrowGatewayStorage storage $ = _getEscrowGatewayStorage();
      if ($.localToExternalToken[localToken] == address(0)) {
        $.localToExternalToken[localToken] = _computeExternalToken(localToken);
      }
    }

    IERC20(localToken).safeTransfer(to, amount);
    emit TokensUnlocked(localToken, to, amount);
  }

  function localToExternalToken(address localToken) external view returns (address) {
    return _getEscrowGatewayStorage().localToExternalToken[localToken];
  }

  function _computeExternalToken(address localToken) internal view returns (address) {
    bytes32 salt;
    assembly {
      salt := localToken
    }
    return Create2.computeAddress(salt, EXTERNAL_TOKEN_INIT_CODE_HASH, COUNTERPART_GATEWAY);
  }

  function _sendToCounterpart(address token, address to, uint256 amount) internal returns (bytes memory message) {
    if (to == address(0)) revert DefaultEscrowGatewayBase_InvalidRecipient();
    EscrowGatewayStorage storage $ = _getEscrowGatewayStorage();
    address externalToken = $.localToExternalToken[token];
    bytes memory deployData;

    if (externalToken == address(0)) {
      externalToken = _computeExternalToken(token);
      (string memory name, string memory symbol, uint8 decimals) = TokenInteropLib.fetchMetadata(token);
      deployData = abi.encode(token, name, symbol, decimals);
    }

    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

    message = abi.encodeCall(IMintGateway.mint, (externalToken, to, amount, deployData));
  }
}
