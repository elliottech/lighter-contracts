// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {LIGHTER_CORE_SYSTEM_ADDR, REENTRANCY_TSLOT} from "../Constants.sol";
import {IDefaultMintGatewayAdmin} from "../interfaces/IDefaultMintGatewayAdmin.sol";
import {IEscrowGateway} from "../interfaces/IEscrowGateway.sol";
import {IEvmInteropManager} from "../interfaces/IEvmInteropManager.sol";
import {IL1CoreMessaging} from "../interfaces/IL1CoreMessaging.sol";
import {IMintGateway} from "../interfaces/IMintGateway.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Config} from "../Config.sol";
import {IGovernance} from "../interfaces/IGovernance.sol";
import {IZkLighter} from "../interfaces/IZkLighter.sol";
import {TxTypes} from "../lib/TxTypes.sol";
import {CanonicalDomain, TokenInteropLib} from "./TokenInteropLib.sol";
import {CoreAssetL1Config} from "../interfaces/IL1InteropManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract L1InteropManager is Initializable, Config {
  using SafeERC20 for IERC20;

  IZkLighter public immutable ZK_LIGHTER;
  IL1CoreMessaging public immutable L1_CORE_MESSAGING;
  address public immutable EVM_INTEROP_MANAGER;

  // Known default gateway addresses (immutable, set at deploy time)
  address public immutable DEFAULT_L1_MINT_GATEWAY;
  address public immutable DEFAULT_EVM_MINT_GATEWAY;
  address public immutable DEFAULT_L1_ESCROW_GATEWAY;
  address public immutable DEFAULT_EVM_ESCROW_GATEWAY;

  struct CoreAssetL1Config {
    CanonicalDomain canonicalDomain;
    address l1Token;
    address coreTokenAdmin;
    uint56 extensionMultiplier;
    uint128 tickSize;
    address l1Gateway;
  }

  struct EvmTokenMetadata {
    string name;
    string symbol;
    uint8 decimals;
  }

  /// @custom:storage-location erc7201:lighter.storage.L1InteropManagerStorage
  struct L1InteropManagerStorage {
    mapping(uint32 assetIndex => CoreAssetL1Config) assetConfigs;
    IGovernance governance;
    mapping(address => uint32) l1TokenToAssetIndex;
    // EVM-native: token metadata delivered via sendTokenInfo, used for L1 wrapper deployment.
    mapping(address evmToken => EvmTokenMetadata) evmNativeTokenMetadata;
    mapping(address evmToken => address) evmApprovedTokenAdmin;
    mapping(address l1Token => address) l1ApprovedTokenAdmin;
    // EVM-native: maps assetIndex to the linked evmToken address (set during finalizeEvmNativeTokenLink).
    // Used in selectEvmNativeGatewayPair to look up token metadata stored by sendTokenInfo.
    mapping(uint32 => address) evmNativeLinkedToken;
  }

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.L1InteropManagerStorage")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant L1InteropManagerStorageLocation = 0x01e4fef8f8c35a85d2686734d34af6845e1387a9686b2b4d5ddfaebc59149d00;

  error L1InteropManager_NotEvmInteropManager();
  error L1InteropManager_CallerNotAuthorized();
  error L1InteropManager_AssetIndexReserved();
  error L1InteropManager_InvalidAssetIndex();
  error L1InteropManager_L1TokenZeroAddress();
  error L1InteropManager_AssetAlreadyRegistered();
  error L1InteropManager_L1TokenAlreadyRegistered();
  error L1InteropManager_AssetNotRegistered();
  error L1InteropManager_NotEvmNative();
  error L1InteropManager_NotCoreTokenAdmin();
  error L1InteropManager_NotEvmTokenAdmin();
  error L1InteropManager_GatewayAlreadySelected();
  error L1InteropManager_EvmGatewayZeroAddress();
  error L1InteropManager_L1GatewayZeroAddress();
  error L1InteropManager_ExpectedWrapperZeroAddress();
  error L1InteropManager_NotL1Native();
  error L1InteropManager_EvmGatewayMustBeDefault();
  error L1InteropManager_UnexpectedWrapperAddress();
  error L1InteropManager_GatewayPairMismatch();
  error L1InteropManager_L1GatewayAlreadySet();
  error L1InteropManager_AlreadyLinked();
  error L1InteropManager_TokenNotLinked();
  error L1InteropManager_NotL1TokenAdmin();
  error L1InteropManager_DirtyUpperBits();
  error L1InteropManager_EthAdminImmutable();
  error L1InteropManager_AssetNotActive();
  error L1InteropManager_EthNotSupported();
  error L1InteropManager_InvalidAssetConfigParams();
  error L1InteropManager_ReentrantCall();

  event AssetRegistered(uint32 indexed assetIndex, CanonicalDomain indexed canonicalDomain, address l1Token);
  event EvmTokenLinkInitiated(uint32 indexed assetIndex, address indexed evmToken);
  event EvmTokenLinkFinalized(uint32 indexed assetIndex, address indexed evmToken);
  event L1NativeGatewayPairSelected(uint32 indexed assetIndex, address indexed l1Gateway, address evmGateway);
  event EvmNativeGatewayPairSelected(uint32 indexed assetIndex, address indexed l1Gateway, address evmGateway);
  event L1NativeGatewayPairFinalized(uint32 indexed assetIndex, address indexed l1Gateway, address wrappedEvmToken);
  event EvmNativeGatewayFinalizedOnL1(uint32 indexed assetIndex, address indexed l1MintGateway, address l1Wrapper);
  event L1ApprovedTokenAdminSet(address indexed token, address admin);
  event EvmApprovedTokenInfoSet(address indexed evmToken, address admin);
  event CoreTokenAdminUpdated(uint32 indexed assetIndex, address newAdmin);
  event DefaultL1MintGatewayTokenImplementationSet(address indexed newImpl);
  event DefaultEvmMintGatewayTokenImplementationRequested(address indexed newImpl);
  event SentToCore(uint32 indexed assetIndex, address indexed from, address indexed to, uint256 amount);
  event ReceivedFromCore(uint32 indexed assetIndex, address indexed to, uint256 amount);

  modifier nonReentrant() {
    bool locked;
    assembly {
      locked := tload(REENTRANCY_TSLOT)
    }
    if (locked) revert L1InteropManager_ReentrantCall();
    assembly {
      tstore(REENTRANCY_TSLOT, 1)
    }
    _;
    assembly {
      tstore(REENTRANCY_TSLOT, 0)
    }
  }

  function _getL1InteropManagerStorage() internal pure returns (L1InteropManagerStorage storage $) {
    assembly {
      $.slot := L1InteropManagerStorageLocation
    }
  }

  modifier onlyGovernance() {
    _onlyGovernance();
    _;
  }

  function _onlyGovernance() internal view {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    $.governance.requireGovernor(msg.sender);
  }

  modifier onlyEvmInteropManager() {
    _onlyEvmInteropManager();
    _;
  }

  function _onlyEvmInteropManager() internal view {
    if (msg.sender != address(ZK_LIGHTER) || ZK_LIGHTER.l2Sender() != EVM_INTEROP_MANAGER) {
      revert L1InteropManager_NotEvmInteropManager();
    }
  }

  modifier onlyCoreSystem() {
    _onlyCoreSystem();
    _;
  }

  function _onlyCoreSystem() internal view {
    if (msg.sender != address(ZK_LIGHTER) || ZK_LIGHTER.l2Sender() != LIGHTER_CORE_SYSTEM_ADDR) {
      revert L1InteropManager_CallerNotAuthorized();
    }
  }

  constructor(
    IZkLighter _zkLighter,
    IL1CoreMessaging _l1CoreMessaging,
    address _evmInteropManager,
    address _defaultL1MintGateway,
    address _defaultEvmMintGateway,
    address _defaultL1EscrowGateway,
    address _defaultEvmEscrowGateway
  ) {
    _disableInitializers();
    ZK_LIGHTER = _zkLighter;
    L1_CORE_MESSAGING = _l1CoreMessaging;
    EVM_INTEROP_MANAGER = _evmInteropManager;
    DEFAULT_L1_MINT_GATEWAY = _defaultL1MintGateway;
    DEFAULT_EVM_MINT_GATEWAY = _defaultEvmMintGateway;
    DEFAULT_L1_ESCROW_GATEWAY = _defaultL1EscrowGateway;
    DEFAULT_EVM_ESCROW_GATEWAY = _defaultEvmEscrowGateway;
  }

  function upgrade(bytes calldata) external {}

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                    ASSET REGISTRATION                      */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  struct AssetConfigParams {
    uint32 assetIndex;
    address coreTokenAdmin;
    uint56 extensionMultiplier;
    uint128 tickSize;
  }

  /// @notice Store L1 config for an L1-native asset. Does not send to Core.
  function registerL1NativeAssetConfig(address l1Token, AssetConfigParams calldata params) external onlyGovernance nonReentrant {
    if (l1Token == address(0)) revert L1InteropManager_L1TokenZeroAddress();
    if (!_hasCode(l1Token)) revert L1InteropManager_InvalidAssetConfigParams();
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    if ($.l1TokenToAssetIndex[l1Token] != 0) revert L1InteropManager_L1TokenAlreadyRegistered();

    _registerAssetConfig(CanonicalDomain.L1, l1Token, params);
    $.l1TokenToAssetIndex[l1Token] = params.assetIndex;
  }

  /// @notice Store L1 config for a Core-native asset. Does not send to Core.
  function registerCoreNativeAssetConfig(AssetConfigParams calldata params) external onlyGovernance nonReentrant {
    _registerAssetConfig(CanonicalDomain.Core, address(0), params);
  }

  /// @notice Store L1 config for an EVM-native asset. Does not send to Core.
  function registerEvmNativeAssetConfig(AssetConfigParams calldata params) external onlyGovernance {
    _registerAssetConfig(CanonicalDomain.EVM, address(0), params);
  }

  function _registerAssetConfig(CanonicalDomain domain, address l1Token, AssetConfigParams calldata p) internal {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();

    if (p.assetIndex == 0) revert L1InteropManager_AssetIndexReserved();
    if (p.assetIndex < MIN_ASSET_INDEX || p.assetIndex > MAX_ASSET_INDEX) revert L1InteropManager_InvalidAssetIndex();
    if (isRegisteredOnL1(p.assetIndex)) revert L1InteropManager_AssetAlreadyRegistered();

    if (p.tickSize == 0 || p.tickSize > MAX_TICK_SIZE) revert L1InteropManager_InvalidAssetConfigParams();
    if (p.extensionMultiplier == 0 || p.extensionMultiplier > MAX_ASSET_EXTENSION_MULTIPLIER) {
      revert L1InteropManager_InvalidAssetConfigParams();
    }

    $.assetConfigs[p.assetIndex] = CoreAssetL1Config({
      canonicalDomain: domain,
      l1Token: l1Token,
      coreTokenAdmin: p.coreTokenAdmin,
      l1Gateway: address(0),
      extensionMultiplier: p.extensionMultiplier,
      tickSize: p.tickSize
    });

    emit AssetRegistered(p.assetIndex, domain, l1Token);
  }

  /// @notice Send L1-native asset registration priority request to Core.
  function registerL1NativeAssetOnCore(
    TxTypes.RegisterAsset calldata _params,
    bytes32 symbol,
    uint8 l1Decimals,
    uint8 coreDecimals,
    uint8 priceDecimals
  ) external onlyGovernance {
    if (!isRegisteredOnL1(_params.assetIndex)) revert L1InteropManager_AssetNotActive();
    CoreAssetL1Config storage cfg = _getL1InteropManagerStorage().assetConfigs[_params.assetIndex];
    if (cfg.canonicalDomain != CanonicalDomain.L1) revert L1InteropManager_NotL1Native();

    _registerL1NativeAssetOnCore(cfg, _params, symbol, l1Decimals, coreDecimals, priceDecimals);
  }

  function _registerL1NativeAssetOnCore(
    CoreAssetL1Config storage cfg,
    TxTypes.RegisterAsset calldata _params,
    bytes32 symbol,
    uint8 l1Decimals,
    uint8 coreDecimals,
    uint8 priceDecimals
  ) private {
    L1_CORE_MESSAGING.registerL1NativeAssetOnCore({
      sender: msg.sender,
      l1Address: cfg.l1Token,
      l1Decimals: l1Decimals,
      coreDecimals: coreDecimals,
      priceDecimals: priceDecimals,
      extensionMultiplier: cfg.extensionMultiplier,
      tickSize: cfg.tickSize,
      symbol: symbol,
      _params: _params
    });
  }

  /// @notice Send Core-native asset registration priority request to Core.
  /// @param coreDecimals Decimal places of Core base amounts, before extensionMultiplier.
  /// @param priceDecimals Decimal places of the index price, from 0 to 16.
  function registerCoreNativeAssetOnCore(
    TxTypes.RegisterAsset calldata _params,
    bytes32 symbol,
    uint8 coreDecimals,
    uint8 priceDecimals
  ) external onlyGovernance {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    if (!isRegisteredOnL1(_params.assetIndex)) revert L1InteropManager_AssetNotActive();
    CoreAssetL1Config storage cfg = $.assetConfigs[_params.assetIndex];
    if (cfg.canonicalDomain != CanonicalDomain.Core) revert L1InteropManager_AssetNotActive();

    L1_CORE_MESSAGING.registerCoreNativeAssetOnCore({
      sender: msg.sender,
      coreDecimals: coreDecimals,
      priceDecimals: priceDecimals,
      extensionMultiplier: cfg.extensionMultiplier,
      tickSize: cfg.tickSize,
      symbol: symbol,
      _params: _params
    });
  }

  /// @notice Send EVM-native asset registration priority request to Core.
  /// @param evmDecimals Governance-supplied decimal places of the canonical EVM token.
  /// @param coreDecimals Decimal places of Core base amounts, before extensionMultiplier.
  /// @param priceDecimals Decimal places of the index price, from 0 to 16.
  function registerEvmNativeAssetOnCore(
    TxTypes.RegisterAsset calldata _params,
    bytes32 symbol,
    uint8 evmDecimals,
    uint8 coreDecimals,
    uint8 priceDecimals
  ) external onlyGovernance {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    if (!isRegisteredOnL1(_params.assetIndex)) revert L1InteropManager_AssetNotActive();
    CoreAssetL1Config storage cfg = $.assetConfigs[_params.assetIndex];
    if (cfg.canonicalDomain != CanonicalDomain.EVM) revert L1InteropManager_NotEvmNative();

    L1_CORE_MESSAGING.registerEvmNativeAssetOnCore({
      sender: msg.sender,
      evmDecimals: evmDecimals,
      coreDecimals: coreDecimals,
      priceDecimals: priceDecimals,
      extensionMultiplier: cfg.extensionMultiplier,
      tickSize: cfg.tickSize,
      symbol: symbol,
      _params: _params
    });
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                   EVM TOKEN LINKING                        */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice EVM-native token linking — Step 1 (L1).
  /// Core token admin links an EVM token to a registered EVM-native asset.
  ///
  /// Linking steps:
  /// 1. [L1] linkEvmNativeToken — sends L1 to EVM  **THIS STEP**
  /// 2. [EVM] onLinkEvmNativeToken — validates, sets evmToken, sends 0x45 to Core
  /// 3. [Core] fulfills 0x45 — sets evmToken on Core, produces L1Call to L1
  /// 4. [L1] finalizeEvmNativeTokenLink — stores evmNativeLinkedToken
  function linkEvmNativeToken(uint32 assetIndex, address evmToken, uint256 gasLimit) external payable nonReentrant {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    CoreAssetL1Config storage cfg = $.assetConfigs[assetIndex];

    if (!isRegisteredOnL1(assetIndex)) revert L1InteropManager_AssetNotRegistered();
    if (cfg.canonicalDomain != CanonicalDomain.EVM) revert L1InteropManager_NotEvmNative();
    if (msg.sender != cfg.coreTokenAdmin) revert L1InteropManager_NotCoreTokenAdmin();
    if (cfg.coreTokenAdmin != $.evmApprovedTokenAdmin[evmToken]) revert L1InteropManager_NotEvmTokenAdmin();
    // Cannot re-link after finalization (Step 4 sets this).
    if ($.evmNativeLinkedToken[assetIndex] != address(0)) revert L1InteropManager_AlreadyLinked();

    bytes memory metadata = abi.encode(cfg.tickSize);

    _sendToEvm(abi.encodeCall(IEvmInteropManager.onLinkEvmNativeToken, (assetIndex, evmToken, metadata)), gasLimit);

    emit EvmTokenLinkInitiated(assetIndex, evmToken);
  }

  /// @notice EVM-native token linking — Step 4 (L1).
  /// Called via Core to L1 L1Call after Core confirms the token link.
  ///
  /// Linking steps:
  /// 1. [L1] linkEvmNativeToken — sends L1 to EVM
  /// 2. [EVM] onLinkEvmNativeToken — validates, sets evmToken, sends 0x45 to Core
  /// 3. [Core] fulfills 0x45 — sets evmToken on Core, produces L1Call to L1
  /// 4. [L1] finalizeEvmNativeTokenLink — stores evmNativeLinkedToken  **THIS STEP**
  function finalizeEvmNativeTokenLink(uint32 assetIndex, address evmToken) external onlyCoreSystem {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();

    // The below check is technically unnecessary since EVM will only let
    // one message through. But we will be defensive anyways.
    if ($.evmNativeLinkedToken[assetIndex] != address(0)) revert L1InteropManager_AlreadyLinked();
    $.evmNativeLinkedToken[assetIndex] = evmToken;

    emit EvmTokenLinkFinalized(assetIndex, evmToken);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*          L1 NATIVE GATEWAY SELECTION FUNCTIONS            */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice L1-native gateway pair selection — Step 1 (L1).
  /// L1-native: l1Gateway is escrow, evmGateway is mint.
  ///
  /// Selection steps:
  /// 1. [L1] selectL1NativeGatewayPair — validates, sends L1 to EVM with metadata  **THIS STEP**
  /// 2. [EVM] onL1NativeGatewaySelection — deploys wrapped token, sets evmConfig, acks to L1
  /// 3. [L1] finalizeL1NativeGatewayPair — sets l1Gateway, transfers escrow, notifies Core
  function selectL1NativeGatewayPair(
    uint32 assetIndex,
    address evmGateway,
    address l1Gateway,
    address expectedEvmWrapperToken,
    uint256 gasLimit
  ) external payable nonReentrant {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    CoreAssetL1Config storage cfg = $.assetConfigs[assetIndex];

    // Gateway and wrapper selections cannot be address(0).
    if (evmGateway == address(0)) revert L1InteropManager_EvmGatewayZeroAddress();
    if (l1Gateway == address(0)) revert L1InteropManager_L1GatewayZeroAddress();
    if (expectedEvmWrapperToken == address(0)) revert L1InteropManager_ExpectedWrapperZeroAddress();

    if (!isRegisteredOnL1(assetIndex)) revert L1InteropManager_AssetNotRegistered();
    // On first call for the asset index, the below check should also imply
    // evmGateway on EvmInteropManager is address(0).
    if (cfg.l1Gateway != address(0)) revert L1InteropManager_GatewayAlreadySelected();
    if (cfg.canonicalDomain != CanonicalDomain.L1) revert L1InteropManager_NotL1Native();

    // Only the core token admin can select gateways.
    if (msg.sender != cfg.coreTokenAdmin) revert L1InteropManager_NotCoreTokenAdmin();

    if (l1Gateway == DEFAULT_L1_ESCROW_GATEWAY) {
      if (evmGateway != DEFAULT_EVM_MINT_GATEWAY) revert L1InteropManager_EvmGatewayMustBeDefault();
      if (expectedEvmWrapperToken != TokenInteropLib.computeCreate2Wrapper(DEFAULT_EVM_MINT_GATEWAY, bytes32(uint256(uint160(cfg.l1Token)))))
        revert L1InteropManager_UnexpectedWrapperAddress();
    } else {
      if (cfg.coreTokenAdmin != $.evmApprovedTokenAdmin[expectedEvmWrapperToken]) revert L1InteropManager_NotEvmTokenAdmin();
    }

    if (IEscrowGateway(l1Gateway).externalGateway() != evmGateway) revert L1InteropManager_GatewayPairMismatch();

    // Serialization: abi.encode(
    //     abi.encode(salt, name, symbol, decimals),  // tokenMetadata — passed to gateway's checkOrDeployToken
    //     tickSize  // config field for EvmInteropManager
    // )
    bytes memory metadata;
    {
      address l1Token = cfg.l1Token;
      (string memory name, string memory symbol, uint8 decimals) = TokenInteropLib.fetchMetadata(l1Token);
      metadata = abi.encode(abi.encode(_toSalt(l1Token), name, symbol, decimals), cfg.tickSize);
    }

    _sendToEvm(
      abi.encodeCall(IEvmInteropManager.onL1NativeGatewaySelection, (assetIndex, evmGateway, l1Gateway, expectedEvmWrapperToken, metadata)),
      gasLimit
    );

    emit L1NativeGatewayPairSelected(assetIndex, l1Gateway, evmGateway);
  }

  /// @notice L1-native gateway pair selection — Step 3 (L1).
  /// Sets l1Gateway, transfers escrowed L1 tokens, notifies Core.
  ///
  /// Selection steps:
  /// 1. [L1] selectL1NativeGatewayPair — sends L1 to EVM with metadata
  /// 2. [EVM] onL1NativeGatewaySelection — deploys wrapped token, sets evmConfig, acks to L1 with l1Gateway
  /// 3. [L1] finalizeL1NativeGatewayPair — sets l1Gateway, notifies Core  **THIS STEP**
  function finalizeL1NativeGatewayPair(uint32 assetIndex, address l1Gateway, address wrappedEvmToken) external onlyEvmInteropManager {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    if ($.assetConfigs[assetIndex].l1Gateway != address(0)) revert L1InteropManager_L1GatewayAlreadySet();

    // Finalize: set l1Gateway on the asset config
    $.assetConfigs[assetIndex].l1Gateway = l1Gateway;

    // Transfer escrowed L1 tokens to the escrow gateway
    address l1Token = $.assetConfigs[assetIndex].l1Token;
    uint256 balance = IERC20(l1Token).balanceOf(address(this));
    if (balance > 0) IERC20(l1Token).safeTransfer(l1Gateway, balance);

    // Notify Core of the EVM link
    L1_CORE_MESSAGING.finalizeEvmWrapperLink(msg.sender, assetIndex, wrappedEvmToken);

    emit L1NativeGatewayPairFinalized(assetIndex, l1Gateway, wrappedEvmToken);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*         EVM NATIVE GATEWAY SELECTION FUNCTIONS            */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice EVM-native gateway pair selection — Step 1 (L1).
  /// EVM-native: l1Gateway is mint, evmGateway is escrow. L1 wrapper is deployed
  /// upfront using metadata delivered via sendTokenInfo.
  ///
  /// @dev Note that since the L1 wrapper is deployed upfront, validation
  /// failure on EVM could lead to that contract just being orphaned / unused.
  ///
  /// Selection steps:
  /// 1. [L1] selectEvmNativeGatewayPair — validates, deploys L1 wrapper, sends L1 to EVM  **THIS STEP**
  /// 2. [EVM] onEvmNativeGatewaySelection — validates, finalizes EVM side, acks to L1
  /// 3. [L1] finalizeEvmNativeGatewayPairOnL1 — activates l1Gateway, notifies Core
  function selectEvmNativeGatewayPair(
    uint32 assetIndex,
    address evmGateway,
    address l1Gateway,
    address expectedL1WrapperToken,
    uint256 gasLimit
  ) external payable nonReentrant {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    CoreAssetL1Config storage cfg = $.assetConfigs[assetIndex];

    // Gateway and wrapper selections cannot be address(0).
    if (evmGateway == address(0)) revert L1InteropManager_EvmGatewayZeroAddress();
    if (l1Gateway == address(0)) revert L1InteropManager_L1GatewayZeroAddress();
    if (expectedL1WrapperToken == address(0)) revert L1InteropManager_ExpectedWrapperZeroAddress();

    if (!isRegisteredOnL1(assetIndex)) revert L1InteropManager_AssetNotRegistered();
    // The below check should also imply evmGateway on EvmInteropManager is address(0).
    if (cfg.l1Gateway != address(0)) revert L1InteropManager_GatewayAlreadySelected();
    if (cfg.canonicalDomain != CanonicalDomain.EVM) revert L1InteropManager_NotEvmNative();

    // Only the core token admin can select gateways.
    if (msg.sender != cfg.coreTokenAdmin) revert L1InteropManager_NotCoreTokenAdmin();

    address evmToken = $.evmNativeLinkedToken[assetIndex];
    if (evmToken == address(0)) revert L1InteropManager_TokenNotLinked();

    if (l1Gateway == DEFAULT_L1_MINT_GATEWAY) {
      if (evmGateway != DEFAULT_EVM_ESCROW_GATEWAY) revert L1InteropManager_EvmGatewayMustBeDefault();
      if (expectedL1WrapperToken != TokenInteropLib.computeCreate2Wrapper(l1Gateway, _toSalt(evmToken))) {
        revert L1InteropManager_UnexpectedWrapperAddress();
      }
    } else {
      if (cfg.coreTokenAdmin != $.l1ApprovedTokenAdmin[expectedL1WrapperToken]) revert L1InteropManager_NotL1TokenAdmin();
    }

    // Verify l1Gateway declares it is paired with evmGateway
    if (IMintGateway(l1Gateway).externalGateway() != evmGateway) revert L1InteropManager_GatewayPairMismatch();

    // Fail fast if the L1 wrapper is already registered to another asset.
    // Also checked in finalizeEvmNativeGatewayPairOnL1 as defense-in-depth.
    if ($.l1TokenToAssetIndex[expectedL1WrapperToken] != 0) revert L1InteropManager_L1TokenAlreadyRegistered();

    // Deploy L1 wrapper upfront using metadata delivered via sendTokenInfo.
    EvmTokenMetadata storage meta = $.evmNativeTokenMetadata[evmToken];
    IMintGateway(l1Gateway).checkOrDeployToken({salt: _toSalt(evmToken), name: meta.name, symbol: meta.symbol, decimals: meta.decimals});

    _sendToEvm(abi.encodeCall(IEvmInteropManager.onEvmNativeGatewaySelection, (assetIndex, evmGateway, l1Gateway, expectedL1WrapperToken)), gasLimit);

    emit EvmNativeGatewayPairSelected(assetIndex, l1Gateway, evmGateway);
  }

  /// @notice EVM-native gateway pair selection — Step 3 (L1).
  /// Called via EVM to L1 withdrawal after EVM validates and finalizes its side.
  ///
  /// Selection steps:
  /// 1. [L1] selectEvmNativeGatewayPair — deploys L1 wrapper, sends L1 to EVM
  /// 2. [EVM] onEvmNativeGatewaySelection — validates, finalizes EVM side, acks to L1 with (l1Gateway, l1Wrapper)
  /// 3. [L1] finalizeEvmNativeGatewayPairOnL1 — activates l1Gateway, notifies Core  **THIS STEP**
  function finalizeEvmNativeGatewayPairOnL1(uint32 assetIndex, address l1MintGateway, address expectedL1Wrapper) external onlyEvmInteropManager {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    if ($.assetConfigs[assetIndex].l1Gateway != address(0)) revert L1InteropManager_L1GatewayAlreadySet();

    // L1 wrapper was already deployed in Step 1 via checkOrDeployToken.
    // Finalize l1Gateway and l1Token on the asset config.
    if ($.l1TokenToAssetIndex[expectedL1Wrapper] != 0) revert L1InteropManager_L1TokenAlreadyRegistered();
    $.assetConfigs[assetIndex].l1Gateway = l1MintGateway;
    $.assetConfigs[assetIndex].l1Token = expectedL1Wrapper;
    $.l1TokenToAssetIndex[expectedL1Wrapper] = assetIndex;

    // Notify Core of the L1 wrapper
    L1_CORE_MESSAGING.finalizeL1WrapperLink(msg.sender, assetIndex, expectedL1Wrapper);

    emit EvmNativeGatewayFinalizedOnL1(assetIndex, l1MintGateway, expectedL1Wrapper);
  }

  /// @notice Governance sets the approved L1 token admin for a given token address.
  /// This mirrors evmApprovedTokenAdmin (populated cross-chain) but indicates
  /// that `admin` controls the L1 wrapper token.
  function setL1ApprovedTokenAdmin(address token, address admin) external onlyGovernance {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    $.l1ApprovedTokenAdmin[token] = admin;

    emit L1ApprovedTokenAdminSet(token, admin);
  }

  /// @notice Stores the token admin and ERC-20 metadata for an EVM token
  /// (delivered cross-chain from EVM via sendTokenInfo).
  /// Prerequisite for EVM-native token linking and custom EVM gateway selections.
  ///
  /// @dev Unconditionally overwrites any token info stored by an earlier call.
  /// L1 messages can execute out of EVM nonce order, so a stale message executed
  /// after a newer one can overwrite the newer admin and metadata.
  function setEvmApprovedTokenInfo(address evmToken, bytes32 slotValue, bytes calldata tokenMetadata) external onlyEvmInteropManager {
    if (uint256(slotValue) >> 160 != 0) revert L1InteropManager_DirtyUpperBits();
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    $.evmApprovedTokenAdmin[evmToken] = address(uint160(uint256(slotValue)));

    (string memory name, string memory symbol, uint8 decimals) = abi.decode(tokenMetadata, (string, string, uint8));
    $.evmNativeTokenMetadata[evmToken] = EvmTokenMetadata(name, symbol, decimals);

    emit EvmApprovedTokenInfoSet(evmToken, address(uint160(uint256(slotValue))));
  }

  function setDefaultL1MintGatewayTokenImplementation(address newImpl) external onlyGovernance {
    IDefaultMintGatewayAdmin(DEFAULT_L1_MINT_GATEWAY).setTokenImplementation(newImpl);
    emit DefaultL1MintGatewayTokenImplementationSet(newImpl);
  }

  function setDefaultEvmMintGatewayTokenImplementation(address newImpl, uint256 gasLimit) external payable onlyGovernance nonReentrant {
    _sendToEvm(abi.encodeCall(IEvmInteropManager.setDefaultMintGatewayTokenImplementation, (newImpl)), gasLimit);
    emit DefaultEvmMintGatewayTokenImplementationRequested(newImpl);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                     TOKEN OPERATIONS                       */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice Governor-controlled core token admin update.
  function setCoreTokenAdmin(uint32 assetIndex, address newAdmin) external onlyGovernance {
    if (assetIndex == NATIVE_ASSET_INDEX) revert L1InteropManager_EthAdminImmutable();
    if (!isRegisteredOnL1(assetIndex)) revert L1InteropManager_AssetNotActive();
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    $.assetConfigs[assetIndex].coreTokenAdmin = newAdmin;

    emit CoreTokenAdminUpdated(assetIndex, newAdmin);
  }

  function sendToCore(uint32 _assetIndex, address to, uint256 amount, TxTypes.RouteType routeType) external payable nonReentrant {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    CoreAssetL1Config memory cfg = $.assetConfigs[_assetIndex];

    // Validation checks
    if (!isActiveOnL1(_assetIndex)) revert TokenInteropLib.TokenInteropLib_AssetNotActive();
    if (to == address(0)) revert TokenInteropLib.TokenInteropLib_RecipientAddressInvalid();
    if (amount == 0 || amount % cfg.tickSize != 0) revert TokenInteropLib.TokenInteropLib_InvalidDepositAmount();

    if (_assetIndex == NATIVE_ASSET_INDEX) {
      if (msg.value != amount) revert TokenInteropLib.TokenInteropLib_InsufficientMsgValue();
    } else {
      if (msg.value != 0) revert TokenInteropLib.TokenInteropLib_InvalidDepositAmount();
      TokenInteropLib.transferIn({
        isCanonicalLocal: cfg.canonicalDomain == CanonicalDomain.L1,
        localToken: cfg.l1Token,
        localGateway: cfg.l1Gateway,
        amount: amount
      });
    }
    uint64 baseAmount = TokenInteropLib.toBaseAmount({amount: amount, tickSize: cfg.tickSize});
    L1_CORE_MESSAGING.registerDeposit{value: msg.value}(msg.sender, to, _assetIndex, routeType, baseAmount);

    emit SentToCore(_assetIndex, msg.sender, to, amount);
  }

  function receiveFromCore(uint32 assetIndex, address to, uint128 baseAmount) external onlyCoreSystem {
    if (assetIndex == NATIVE_ASSET_INDEX) revert L1InteropManager_EthNotSupported();

    if (!isActiveOnL1(assetIndex)) revert TokenInteropLib.TokenInteropLib_AssetNotActive();

    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    CoreAssetL1Config memory cfg = $.assetConfigs[assetIndex];
    uint256 amount = uint256(baseAmount) * uint256(cfg.tickSize);

    // We maintain the invariant that if this function is called,
    // cfg.l1Gateway == address(0) implies cfg.canonicalDomain ==
    // CanonicalDomain.L1.
    if (cfg.l1Gateway != address(0)) {
      if (cfg.canonicalDomain == CanonicalDomain.L1) {
        // L1-native: escrow moved to gateway during selection
        IEscrowGateway(cfg.l1Gateway).unlock(cfg.l1Token, to, amount);
      } else {
        // Non-L1-native: mint via gateway
        IMintGateway(cfg.l1Gateway).mint(cfg.l1Token, to, amount, "");
      }
    } else {
      // No gateway selected yet: L1InteropManager still holds L1-native tokens directly
      assert(cfg.canonicalDomain == CanonicalDomain.L1);
      SafeERC20.safeTransfer(IERC20(cfg.l1Token), to, amount);
    }

    emit ReceivedFromCore(assetIndex, to, amount);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                           VIEW                             */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  /// @notice Whether an asset config has been registered on L1 for this asset index.
  function isRegisteredOnL1(uint32 assetIndex) public view returns (bool) {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    return $.assetConfigs[assetIndex].canonicalDomain != CanonicalDomain.None;
  }

  /// @notice Whether the asset has an L1 token address set (either the canonical token
  /// for L1-native assets, or a wrapper deployed by a gateway for other domains).
  /// An asset can be active on Core before it is active on L1 — e.g. an EVM-native
  /// asset is registered on Core immediately but only becomes active on L1 once a
  /// gateway is selected and deploys a wrapper.
  function isActiveOnL1(uint32 assetIndex) public view returns (bool) {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    return $.assetConfigs[assetIndex].l1Token != address(0);
  }

  function getAssetConfig(uint32 assetIndex) external view returns (CoreAssetL1Config memory) {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    return $.assetConfigs[assetIndex];
  }

  function l1TokenToAssetIndex(address token) external view returns (uint32) {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    return $.l1TokenToAssetIndex[token];
  }

  function evmApprovedTokenAdmin(address evmToken) external view returns (address) {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    return $.evmApprovedTokenAdmin[evmToken];
  }

  function getEvmNativeTokenMetadata(address evmToken) external view returns (EvmTokenMetadata memory) {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    return $.evmNativeTokenMetadata[evmToken];
  }

  function l1ApprovedTokenAdmin(address l1Token) external view returns (address) {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    return $.l1ApprovedTokenAdmin[l1Token];
  }

  function evmNativeLinkedToken(uint32 assetIndex) external view returns (address) {
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    return $.evmNativeLinkedToken[assetIndex];
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                         INTERNAL                           */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function _toSalt(address token) private pure returns (bytes32 salt) {
    assembly {
      salt := token
    }
  }

  /// @dev Sends a message to EVM_INTEROP_MANAGER via ZkLighter priority request.
  /// The message arrives on EVM with msg.sender == alias(address(this)).
  function _sendToEvm(bytes memory data, uint256 gasLimit) private {
    ZK_LIGHTER.addEvmPriorityRequest{value: msg.value}({
      to: EVM_INTEROP_MANAGER,
      value: 0,
      depositAmount: 0,
      gasLimit: gasLimit,
      isCreation: false,
      refundAddress: msg.sender,
      data: data
    });
  }
}
