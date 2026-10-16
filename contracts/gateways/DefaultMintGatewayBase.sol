// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IEscrowGateway} from "../interfaces/IEscrowGateway.sol";
import {IMintGateway} from "../interfaces/IMintGateway.sol";
import {TokenInteropLib} from "../interop/TokenInteropLib.sol";
import {LighterWrappedERC20V1} from "../token/LighterWrappedERC20V1.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title DefaultMintGatewayBase
/// @notice Shared logic for L1-native / EVM-native mint gateways that deploy wrapped
/// tokens via CREATE2 and bridge them back through an escrow counterpart.
abstract contract DefaultMintGatewayBase is Initializable, IMintGateway, IBeacon {
  using SafeERC20 for IERC20;

  /// @custom:storage-location erc7201:lighter.storage.MintGateway
  struct MintGatewayStorage {
    mapping(address localToken => address) externalToken;
    address tokenImplementation;
  }

  address public immutable COUNTERPART_GATEWAY;

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.MintGateway")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant MintGatewayStorageLocation = 0x8143d3d84c86e4c1581b85ed82bea9d07a26e2d3a93b166ec7287b91be602000;

  function _getMintGatewayStorage() private pure returns (MintGatewayStorage storage $) {
    assembly {
      $.slot := MintGatewayStorageLocation
    }
  }

  uint256 private constant _REENTRANCY_TSLOT = 0x00;

  event TokensMinted(address indexed localToken, address indexed to, uint256 amount);
  event TokensSent(address indexed localToken, address indexed to, uint256 amount);

  error DefaultMintGatewayBase_UnauthorizedReceive();
  error DefaultMintGatewayBase_TokenNotBridged();
  error DefaultMintGatewayBase_InvalidRecipient();
  error DefaultMintGatewayBase_UnauthorizedManagerBurn();
  error DefaultMintGatewayBase_UnauthorizedSetImplementation();
  error DefaultMintGatewayBase_MissingDeployData();
  error DefaultMintGatewayBase_ReentrantCall();
  error DefaultMintGatewayBase_InvalidImplementation();

  modifier nonReentrant() {
    bool locked;
    assembly {
      locked := tload(_REENTRANCY_TSLOT)
    }
    if (locked) revert DefaultMintGatewayBase_ReentrantCall();
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
  }

  function _initializeDefaultMintGatewayBase(address tokenImplementation) internal {
    _getMintGatewayStorage().tokenImplementation = tokenImplementation;
  }

  /// @dev Returns the local interop manager address used for auth.
  function _interopManager() internal view virtual returns (address);

  /// @dev Returns true when `msg.sender` is the cross-chain messenger relaying
  /// a call from the counterpart escrow gateway.
  function _isCounterpartSender() internal view virtual returns (bool);

  function _sendToCounterpart(address token, address to, uint256 amount) internal returns (bytes memory message) {
    if (to == address(0)) revert DefaultMintGatewayBase_InvalidRecipient();
    address extToken = _getMintGatewayStorage().externalToken[token];
    if (extToken == address(0)) revert DefaultMintGatewayBase_TokenNotBridged();

    IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    LighterWrappedERC20V1(token).externalBurn(amount);

    message = abi.encodeCall(IEscrowGateway.unlock, (extToken, to, amount));
  }

  /// @inheritdoc IMintGateway
  function externalGateway() external view override returns (address) {
    return COUNTERPART_GATEWAY;
  }

  /// @notice Computes the deterministic CREATE2 address for a wrapped token.
  function computeTokenAddress(address _externalToken) public view returns (address) {
    return TokenInteropLib.computeCreate2Wrapper(address(this), _salt(_externalToken));
  }

  function _salt(address token) internal pure returns (bytes32 s) {
    assembly {
      s := token
    }
  }

  /// @inheritdoc IMintGateway
  function checkOrDeployToken(bytes32 salt, string calldata name, string calldata symbol, uint8 decimals) external override {
    if (msg.sender != _interopManager()) revert DefaultMintGatewayBase_UnauthorizedReceive();

    address extToken = _fromSalt(salt);
    address localToken = computeTokenAddress(extToken);
    if (localToken.code.length == 0) {
      address deployed = _deployAndStoreToken(extToken, name, symbol, decimals);
      assert(deployed == localToken);
    }
  }

  function _fromSalt(bytes32 s) internal pure returns (address token) {
    assembly {
      token := s
    }
  }

  /// @inheritdoc IMintGateway
  /// @dev Two callers are authorized:
  ///   1. The local interop manager — always passes empty data (token deployed via checkOrDeployToken).
  ///   2. The counterpart escrow gateway (via messenger) — may pass deploy data for lazy deployment.
  function mint(address localToken, address to, uint256 amount, bytes calldata data) external override {
    if (!_isCounterpartSender() && msg.sender != _interopManager()) revert DefaultMintGatewayBase_UnauthorizedReceive();

    if (localToken.code.length == 0) {
      if (data.length == 0) revert DefaultMintGatewayBase_MissingDeployData();

      (address extToken, string memory name, string memory symbol, uint8 decimals) = abi.decode(data, (address, string, string, uint8));

      address deployed = _deployAndStoreToken(extToken, name, symbol, decimals);
      assert(deployed == localToken);
    }

    LighterWrappedERC20V1(localToken).externalMint(to, amount);

    emit TokensMinted(localToken, to, amount);
  }

  /// @dev Deploy a wrapped token via CREATE2, initialize it, and register the external token mapping.
  function _deployAndStoreToken(address extToken, string memory name, string memory symbol, uint8 decimals) internal returns (address localToken) {
    localToken = address(new BeaconProxy{salt: _salt(extToken)}(address(this), ""));
    LighterWrappedERC20V1(localToken).initialize(name, symbol, decimals);
    _getMintGatewayStorage().externalToken[localToken] = extToken;
  }

  /// @inheritdoc IMintGateway
  function managerBurn(address localToken, uint256 amount) external override {
    if (msg.sender != _interopManager()) revert DefaultMintGatewayBase_UnauthorizedManagerBurn();
    LighterWrappedERC20V1(localToken).externalBurn(amount);
  }

  function implementation() external view virtual override returns (address) {
    return _getMintGatewayStorage().tokenImplementation;
  }

  function externalToken(address token) external view returns (address) {
    return _getMintGatewayStorage().externalToken[token];
  }

  function setTokenImplementation(address newImpl) external {
    if (msg.sender != _interopManager()) revert DefaultMintGatewayBase_UnauthorizedSetImplementation();
    if (newImpl.code.length == 0) revert DefaultMintGatewayBase_InvalidImplementation();
    _getMintGatewayStorage().tokenImplementation = newImpl;
  }
}
