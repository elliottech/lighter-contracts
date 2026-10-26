// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Burner} from "../Burner.sol";
import {EVM_L1_REFUND_CLAIMER_ADDR, EVM_MINT_GATEWAY_ADDR, LIGHTER_CORE_SYSTEM_ADDR, READ_CORE} from "../Constants.sol";
import {IDefaultMintGatewayAdmin} from "../interfaces/IDefaultMintGatewayAdmin.sol";
import {IEscrowGateway} from "../interfaces/IEscrowGateway.sol";
import {IEvmL1RefundClaimer} from "../interfaces/IEvmL1RefundClaimer.sol";
import {IEvmToCoreEntrypoint} from "../interfaces/IEvmToCoreEntrypoint.sol";
import {IEvmToL1Messenger} from "../interfaces/IEvmToL1Messenger.sol";
import {IL1InteropManager} from "../interfaces/IL1InteropManager.sol";
import {IMintGateway} from "../interfaces/IMintGateway.sol";
import {TxTypes} from "../lib/TxTypes.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Config} from "../Config.sol";
import {CanonicalDomain, TokenInteropLib} from "./TokenInteropLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract EvmInteropManager is Initializable, Config {
  using SafeERC20 for IERC20;

  error EvmInteropManager_CallerNotAuthorized();
  error EvmInteropManager_AlreadyLinked();
  error EvmInteropManager_EvmTokenAlreadyRegistered();
  error EvmInteropManager_GatewayPairMismatch();
  error EvmInteropManager_AssetNotRegisteredOnCore();
  error EvmInteropManager_EvmTokenNotLinkedOnCore();
  error EvmInteropManager_EvmGatewayAlreadySet();
  error EvmInteropManager_EvmTokenNotLinked();
  error EvmInteropManager_EthNotSupported();
  error EvmInteropManager_ReentrantCall();
  error EvmInteropManager_CoreReadFailed();

  event TokenInfoSent(address indexed evmToken);
  event EvmNativeTokenLinked(uint32 indexed assetIndex, address indexed evmToken);
  event L1NativeGatewaySet(uint32 indexed assetIndex, address indexed evmGateway, address evmToken);
  event EvmNativeGatewayFinalized(uint32 indexed assetIndex, address indexed evmEscrowGateway);
  event SentToCore(uint32 indexed assetIndex, address indexed from, address indexed to, uint256 amount);
  event SentToEvm(uint32 indexed assetIndex, address indexed from, address indexed evmRecipient, uint64 baseAmount);
  event ReceivedFromCore(uint32 indexed assetIndex, address indexed to, uint256 amount);
  event L1AccountRefundReceived(uint32 indexed assetIndex, address indexed l1Address, uint128 baseAmount);

  struct CoreAssetEvmConfig {
    CanonicalDomain canonicalDomain;
    address evmToken;
    address evmGateway;
    uint128 tickSize;
  }

  /// @custom:storage-location erc7201:lighter.storage.EvmInteropManagerStorage
  struct EvmInteropManagerStorage {
    mapping(uint32 assetIndex => CoreAssetEvmConfig) assetConfigs;
    mapping(address => uint32) evmTokenToAssetIndex;
  }

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.EvmInteropManagerStorage")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant EvmInteropManagerStorageLocation = 0xdf6b12daef9ad18a4c185196e3345432ead6e9b8504358077ce033c13d66b400;

  uint160 private constant ALIAS_OFFSET = uint160(0x1111000000000000000000000000000000001111);

  IEvmToL1Messenger public immutable EVM_TO_L1_MESSENGER;
  IEvmToCoreEntrypoint public immutable EVM_TO_CORE_ENTRYPOINT;
  address public immutable L1_INTEROP_MANAGER;
  address public immutable DEFAULT_L1_MINT_GATEWAY;

  constructor(
    IEvmToL1Messenger _evmToL1Messenger,
    IEvmToCoreEntrypoint _evmToCoreEntrypoint,
    address _l1InteropManager,
    address _defaultL1MintGateway
  ) {
    _disableInitializers();
    EVM_TO_L1_MESSENGER = _evmToL1Messenger;
    EVM_TO_CORE_ENTRYPOINT = _evmToCoreEntrypoint;
    L1_INTEROP_MANAGER = _l1InteropManager;
    DEFAULT_L1_MINT_GATEWAY = _defaultL1MintGateway;
  }

  function initialize() external initializer {
    EvmInteropManagerStorage storage $ = _getEvmInteropManagerStorage();
    $.assetConfigs[NATIVE_ASSET_INDEX] = CoreAssetEvmConfig({
      canonicalDomain: CanonicalDomain.L1,
      evmToken: ETH_ADDRESS,
      evmGateway: address(0),
      tickSize: ETH_TICK_SIZE
    });
    $.evmTokenToAssetIndex[ETH_ADDRESS] = NATIVE_ASSET_INDEX;
  }

  function _getEvmInteropManagerStorage() private pure returns (EvmInteropManagerStorage storage $) {
    assembly {
      $.slot := EvmInteropManagerStorageLocation
    }
  }

  uint256 private constant _REENTRANCY_TSLOT = 0x00;

  modifier nonReentrant() {
    bool locked;
    assembly {
      locked := tload(_REENTRANCY_TSLOT)
    }
    if (locked) revert EvmInteropManager_ReentrantCall();
    assembly {
      tstore(_REENTRANCY_TSLOT, 1)
    }
    _;
    assembly {
      tstore(_REENTRANCY_TSLOT, 0)
    }
  }

  modifier onlyCoreSystemAddress() {
    if (msg.sender != LIGHTER_CORE_SYSTEM_ADDR) revert EvmInteropManager_CallerNotAuthorized();
    _;
  }

  modifier onlyL1InteropManager() {
    if (_undoL1ToL2Alias(msg.sender) != L1_INTEROP_MANAGER) revert EvmInteropManager_CallerNotAuthorized();
    _;
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                  EVM NATIVE TOKEN LINKING                  */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice Sends the token admin slot value and ERC-20 metadata for
  /// `evmToken` to L1 in a single message. The chain's state transition
  /// function replaces the bytes32(0) placeholder with the actual
  /// TOKEN_ADMIN_SLOT value.
  /// Prerequisite for EVM-native token linking and custom gateway selections.
  ///
  /// @dev This function is permissionless, and each call creates an independently
  /// executable L1 message. L1 does not enforce execution in EVM nonce order,
  /// while each message overwrites the token's previously stored admin and
  /// metadata. A stale message executed after a newer one can therefore restore
  /// stale token info. It is left up to the token admin to account for this.
  function sendTokenInfo(address evmToken) external nonReentrant {
    (string memory name, string memory symbol, uint8 decimals) = TokenInteropLib.fetchMetadata(evmToken);
    bytes memory tokenMetadata = abi.encode(name, symbol, decimals);

    bytes memory data = abi.encodeCall(IL1InteropManager.setEvmApprovedTokenInfo, (evmToken, bytes32(0), tokenMetadata));
    EVM_TO_L1_MESSENGER.sendTokenInfo(L1_INTEROP_MANAGER, data);

    emit TokenInfoSent(evmToken);
  }

  /// @notice EVM-native token linking — Step 2 (EVM).
  /// Validates, sets evmToken on the asset config, and notifies Core.
  ///
  /// Linking steps:
  /// 1. [L1] linkEvmNativeToken — sends L1 to EVM
  /// 2. [EVM] onLinkEvmNativeToken — validates, sets evmToken, sends 0x45 to Core  **THIS STEP**
  /// 3. [Core] fulfills 0x45 — sets evmToken on Core, produces L1Call to L1
  /// 4. [L1] finalizeEvmNativeTokenLink — stores evmNativeLinkedToken
  ///
  /// @dev One-winner gate: `evmToken == address(0)` check ensures only the first
  /// successful attempt commits. Subsequent attempts revert.
  function onLinkEvmNativeToken(uint32 assetIndex, address evmToken, bytes calldata metadata) external onlyL1InteropManager {
    EvmInteropManagerStorage storage $ = _getEvmInteropManagerStorage();

    // The L1InteropManager only gates initiation of token linking on L1
    // *registration*. There is no guarantee that asset registration message
    // on Core has succeeded. Thus, we make a sync read to Core to check the
    // success of the registration.
    (bool active, ) = isActiveOnCore(assetIndex);
    if (!active) revert EvmInteropManager_AssetNotRegisteredOnCore();

    if ($.assetConfigs[assetIndex].evmToken != address(0)) revert EvmInteropManager_AlreadyLinked();
    if ($.evmTokenToAssetIndex[evmToken] != 0) revert EvmInteropManager_EvmTokenAlreadyRegistered();

    uint128 tickSize = abi.decode(metadata, (uint128));

    $.assetConfigs[assetIndex] = CoreAssetEvmConfig({
      canonicalDomain: CanonicalDomain.EVM,
      evmToken: evmToken,
      evmGateway: address(0),
      tickSize: tickSize
    });
    $.evmTokenToAssetIndex[evmToken] = assetIndex;

    emit EvmNativeTokenLinked(assetIndex, evmToken);

    // Notify Core via EVM to Core write (0x45)
    EVM_TO_CORE_ENTRYPOINT.finalizeEvmLink(assetIndex, evmToken);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*           L1 NATIVE GATEWAY SELECTION FUNCTIONS            */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice L1-native gateway pair selection — Step 2 (EVM).
  /// Deploys wrapped token via gateway, sets full evmConfig, acks to L1 with l1Gateway.
  ///
  /// Selection steps:
  /// 1. [L1] selectL1NativeGatewayPair — sends L1 to EVM with metadata
  /// 2. [EVM] onL1NativeGatewaySelection — deploys wrapped token, sets evmConfig, acks to L1 with l1Gateway  **THIS STEP**
  /// 3. [L1] finalizeL1NativeGatewayPair — sets l1Gateway, transfers escrow, notifies Core
  function onL1NativeGatewaySelection(
    uint32 assetIndex,
    address evmGateway,
    address l1Gateway,
    address expectedEvmWrapper,
    bytes calldata metadata
  ) external onlyL1InteropManager {
    EvmInteropManagerStorage storage $ = _getEvmInteropManagerStorage();

    // The L1InteropManager only gates initiation of gateway pair
    // selection on L1 *registration*. There is no guarantee that asset
    // registration message on Core has succeeded. Thus, we make a sync read
    // to Core to check the success of the registration.
    (bool active, ) = isActiveOnCore(assetIndex);
    if (!active) revert EvmInteropManager_AssetNotRegisteredOnCore();

    // One-winner gate: only the first successful attempt can set evmGateway.
    if ($.assetConfigs[assetIndex].evmGateway != address(0)) revert EvmInteropManager_EvmGatewayAlreadySet();

    // Decode: tokenMetadata (for gateway) + config fields (for InteropManager)
    (bytes memory tokenMetadata, uint128 tickSize) = abi.decode(metadata, (bytes, uint128));

    // Verify evmGateway declares it is paired with l1Gateway
    if (IMintGateway(evmGateway).externalGateway() != l1Gateway) revert EvmInteropManager_GatewayPairMismatch();

    if ($.evmTokenToAssetIndex[expectedEvmWrapper] != 0) revert EvmInteropManager_EvmTokenAlreadyRegistered();

    // Deploy the wrapped token via the gateway
    {
      (bytes32 salt, string memory name, string memory symbol, uint8 decimals) = abi.decode(tokenMetadata, (bytes32, string, string, uint8));
      IMintGateway(evmGateway).checkOrDeployToken({salt: salt, name: name, symbol: symbol, decimals: decimals});
    }

    // Register full asset config
    $.assetConfigs[assetIndex] = CoreAssetEvmConfig({
      canonicalDomain: CanonicalDomain.L1,
      evmToken: expectedEvmWrapper,
      evmGateway: evmGateway,
      tickSize: tickSize
    });
    $.evmTokenToAssetIndex[expectedEvmWrapper] = assetIndex;

    emit L1NativeGatewaySet(assetIndex, evmGateway, expectedEvmWrapper);

    EVM_TO_L1_MESSENGER.initiateWithdrawal(
      L1_INTEROP_MANAGER,
      abi.encodeCall(IL1InteropManager.finalizeL1NativeGatewayPair, (assetIndex, l1Gateway, expectedEvmWrapper))
    );
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*          EVM NATIVE GATEWAY SELECTION FUNCTIONS            */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice EVM-native gateway pair selection — Step 2 (EVM).
  /// Validates gateway, finalizes EVM side, acks to L1 with l1MintGateway + expectedL1Wrapper.
  ///
  /// Selection steps:
  /// 1. [L1] selectEvmNativeGatewayPair — deploys L1 wrapper, sends L1 to EVM
  /// 2. [EVM] onEvmNativeGatewaySelection — validates, finalizes EVM side, acks to L1  **THIS STEP**
  /// 3. [L1] finalizeEvmNativeGatewayPairOnL1 — activates l1Gateway, notifies Core
  ///
  /// @dev If validation fails, the tx reverts and the admin retries step 1 on
  /// L1 with different inputs. If validation succeeds, EVM side is finalized
  /// (evmGateway set, escrow transferred). Exactly one attempt can win since
  /// subsequent attempts fail the evmGateway == address(0) check.
  function onEvmNativeGatewaySelection(
    uint32 assetIndex,
    address evmEscrowGateway,
    address l1MintGateway,
    address expectedL1Wrapper
  ) external onlyL1InteropManager {
    EvmInteropManagerStorage storage $ = _getEvmInteropManagerStorage();

    // By the time gateway selection is initiated on L1, it is already
    // guaranteed that the Core asset exists and that the EVM token has been
    // finalized on L1. But we will be defensive anyways.
    if (!isActiveOnCoreAndLinked(assetIndex)) revert EvmInteropManager_EvmTokenNotLinkedOnCore();

    // Only one attempt can finalize. The one-winner gate handles replay prevention.
    if ($.assetConfigs[assetIndex].evmGateway != address(0)) revert EvmInteropManager_EvmGatewayAlreadySet();

    // Verify evmEscrowGateway declares it is paired with l1MintGateway
    if (IEscrowGateway(evmEscrowGateway).externalGateway() != l1MintGateway) {
      revert EvmInteropManager_GatewayPairMismatch();
    }

    // evmToken must be set locally (via onLinkEvmNativeToken)
    address evmToken = $.assetConfigs[assetIndex].evmToken;
    if (evmToken == address(0)) revert EvmInteropManager_EvmTokenNotLinked();

    // Finalize EVM side: set evmGateway and transfer escrow
    $.assetConfigs[assetIndex].evmGateway = evmEscrowGateway;
    uint256 balance = IERC20(evmToken).balanceOf(address(this));
    if (balance > 0) IERC20(evmToken).safeTransfer(evmEscrowGateway, balance);

    emit EvmNativeGatewayFinalized(assetIndex, evmEscrowGateway);

    EVM_TO_L1_MESSENGER.initiateWithdrawal(
      L1_INTEROP_MANAGER,
      abi.encodeCall(IL1InteropManager.finalizeEvmNativeGatewayPairOnL1, (assetIndex, l1MintGateway, expectedL1Wrapper))
    );
  }

  function setDefaultMintGatewayTokenImplementation(address newImpl) external onlyL1InteropManager {
    IDefaultMintGatewayAdmin(EVM_MINT_GATEWAY_ADDR).setTokenImplementation(newImpl);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                     TOKEN OPERATIONS                       */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function sendToCore(
    uint32 _assetIndex,
    address to,
    bool isL1Account,
    uint256 amount,
    TxTypes.RouteType routeType
  ) public payable nonReentrant returns (uint64 reqId) {
    EvmInteropManagerStorage storage $ = _getEvmInteropManagerStorage();
    CoreAssetEvmConfig memory c = $.assetConfigs[_assetIndex];

    // Validation checks
    if (!isActiveOnCoreAndLinked(_assetIndex)) revert TokenInteropLib.TokenInteropLib_AssetNotActive();
    if (to == address(0)) revert TokenInteropLib.TokenInteropLib_RecipientAddressInvalid();
    if (amount == 0 || amount % c.tickSize != 0) revert TokenInteropLib.TokenInteropLib_InvalidDepositAmount();

    if (_assetIndex == NATIVE_ASSET_INDEX) {
      if (msg.value != amount) revert TokenInteropLib.TokenInteropLib_InsufficientMsgValue();
      // Burn ETH — Core credits the balance without holding escrowed ETH on EVM
      new Burner{value: amount}();
    } else {
      if (msg.value != 0) revert TokenInteropLib.TokenInteropLib_InvalidDepositAmount();
      TokenInteropLib.transferIn({
        isCanonicalLocal: c.canonicalDomain == CanonicalDomain.EVM,
        localToken: c.evmToken,
        localGateway: c.evmGateway,
        amount: amount
      });
    }

    uint64 baseAmount = TokenInteropLib.toBaseAmount({amount: amount, tickSize: c.tickSize});

    reqId = EVM_TO_CORE_ENTRYPOINT.registerSendToCore({
      sender: msg.sender,
      assetIndex: _assetIndex,
      to: to,
      isL1Account: isL1Account,
      routeType: routeType,
      baseAmount: baseAmount
    });

    emit SentToCore(_assetIndex, msg.sender, to, amount);
  }

  /// @dev This function can technically be re-entered, but will eventually fail because of nonReentrant on sendToCore.
  function sendToCoreWithPermit(
    uint32 _assetIndex,
    address to,
    bool isL1Account,
    uint256 amount,
    TxTypes.RouteType routeType,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external returns (uint64 reqId) {
    EvmInteropManagerStorage storage $ = _getEvmInteropManagerStorage();
    address evmToken = $.assetConfigs[_assetIndex].evmToken;

    // Allow permit frontruns or already-set allowances to fall through to transferIn.
    try IERC20Permit(evmToken).permit({owner: msg.sender, spender: address(this), value: amount, deadline: deadline, v: v, r: r, s: s}) {} catch {}

    reqId = sendToCore(_assetIndex, to, isL1Account, amount, routeType);
  }

  /// @notice Requests a transfer from the sender's Core account to an EVM
  /// recipient after validating the asset is active and linked on EVM.
  function sendToEvm(
    uint48 accountIndex,
    uint32 assetIndex,
    address evmRecipient,
    TxTypes.RouteType routeType,
    uint64 baseAmount
  ) external nonReentrant returns (uint64 reqId) {
    if (!isActiveOnCoreAndLinked(assetIndex)) revert TokenInteropLib.TokenInteropLib_AssetNotActive();
    if (evmRecipient == address(0)) revert TokenInteropLib.TokenInteropLib_RecipientAddressInvalid();
    if (baseAmount == 0) revert TokenInteropLib.TokenInteropLib_InvalidDepositAmount();

    reqId = EVM_TO_CORE_ENTRYPOINT.registerSendToEvm({
      sender: msg.sender,
      accountIndex: accountIndex,
      assetIndex: assetIndex,
      evmRecipient: evmRecipient,
      routeType: routeType,
      baseAmount: baseAmount
    });
    emit SentToEvm(assetIndex, msg.sender, evmRecipient, baseAmount);
  }

  function receiveFromCore(uint32 assetIndex, address to, uint128 baseAmount) external onlyCoreSystemAddress nonReentrant {
    _receiveFromCore(assetIndex, to, baseAmount);
  }

  function receiveL1AccountRefund(address l1Address, uint32 assetIndex, uint128 baseAmount) external onlyCoreSystemAddress nonReentrant {
    _receiveFromCore({assetIndex: assetIndex, to: EVM_L1_REFUND_CLAIMER_ADDR, baseAmount: baseAmount});
    IEvmL1RefundClaimer(EVM_L1_REFUND_CLAIMER_ADDR).creditClaimFromCore({l1Address: l1Address, assetIndex: assetIndex, baseAmount: baseAmount});

    emit L1AccountRefundReceived(assetIndex, l1Address, baseAmount);
  }

  function _receiveFromCore(uint32 assetIndex, address to, uint128 baseAmount) private {
    if (assetIndex == NATIVE_ASSET_INDEX) revert EvmInteropManager_EthNotSupported();
    if (!isActiveOnCoreAndLinked(assetIndex)) revert TokenInteropLib.TokenInteropLib_AssetNotActive();

    EvmInteropManagerStorage storage $ = _getEvmInteropManagerStorage();
    CoreAssetEvmConfig storage c = $.assetConfigs[assetIndex];
    uint256 amount = uint256(baseAmount) * uint256(c.tickSize);
    address evmToken = c.evmToken;
    address evmGateway = c.evmGateway;

    // We maintain the invariant that if this function is called,
    // evmGateway == address(0) implies canonicalDomain == CanonicalDomain.EVM.
    if (evmGateway != address(0)) {
      if (c.canonicalDomain == CanonicalDomain.EVM) {
        // EVM-native: escrow moved to gateway during selection
        IEscrowGateway(evmGateway).unlock(evmToken, to, amount);
      } else {
        // Non-EVM-native: mint via gateway
        IMintGateway(evmGateway).mint(evmToken, to, amount, "");
      }
    } else {
      // No gateway selected yet: EvmInteropManager still holds EVM-native tokens directly
      assert(c.canonicalDomain == CanonicalDomain.EVM);
      SafeERC20.safeTransfer(IERC20(evmToken), to, amount);
    }

    emit ReceivedFromCore(assetIndex, to, amount);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                           VIEW                             */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice Whether the asset is registered on Core (priority request was processed),
  /// and the EVM token Core has linked to it (`address(0)` until the link is finalized on Core).
  /// @dev Reverts if the READ_CORE call fails: a failed read is an error, not a missing asset.
  function isActiveOnCore(uint32 assetIndex) public view returns (bool, address) {
    if (assetIndex == NATIVE_ASSET_INDEX) return (true, ETH_ADDRESS);

    (bool success, bytes memory data) = address(READ_CORE).staticcall(abi.encodePacked(bytes2(0x0004), assetIndex));
    if (!success) revert EvmInteropManager_CoreReadFailed();

    (bool found, bytes memory reply) = abi.decode(data, (bool, bytes));
    if (!found) return (false, address(0));

    address evmToken = abi.decode(reply, (address));
    return (true, evmToken);
  }

  /// @notice Whether the asset is registered on Core AND the EVM token link
  /// has been finalized on Core (i.e., Core knows about the EVM token).
  function isActiveOnCoreAndLinked(uint32 assetIndex) public view returns (bool) {
    (bool isActive, address evmToken) = isActiveOnCore(assetIndex);

    if (!isActive) return false;

    if (evmToken == address(0)) return false;

    EvmInteropManagerStorage storage $ = _getEvmInteropManagerStorage();
    assert(evmToken == $.assetConfigs[assetIndex].evmToken);

    return true;
  }

  function getAssetConfig(uint32 assetIndex) external view returns (CoreAssetEvmConfig memory) {
    EvmInteropManagerStorage storage $ = _getEvmInteropManagerStorage();
    return $.assetConfigs[assetIndex];
  }

  function evmTokenToAssetIndex(address token) external view returns (uint32) {
    EvmInteropManagerStorage storage $ = _getEvmInteropManagerStorage();
    return $.evmTokenToAssetIndex[token];
  }

  function _undoL1ToL2Alias(address l2Address) private pure returns (address l1Address) {
    unchecked {
      l1Address = address(uint160(l2Address) - ALIAS_OFFSET);
    }
  }
}
