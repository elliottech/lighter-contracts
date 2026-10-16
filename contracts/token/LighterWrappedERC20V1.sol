// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

/// @title LighterWrappedERC20V1
/// @notice Initializable ERC20 implementation for beacon proxies deployed by mint gateways.
///
/// Deployment model:
/// - A mint gateway (DefaultEvmMintGateway or DefaultL1MintGateway) deploys a BeaconProxy per bridged token.
/// - Each BeaconProxy delegatecalls to this implementation, resolved via the gateway's
/// `implementation()` function (the gateway acts as the beacon).
/// - The gateway calls `initialize` immediately after deployment, becoming the sole
/// mint/burn authority for that proxy.
///
/// Upgradeability:
/// - Governance can deploy a new implementation (e.g. LighterWrappedERC20V2) and update
/// the gateway's `tokenImplementation` pointer. All proxies upgrade atomically since
/// they resolve their implementation from the beacon on every call.
/// - This contract calls `_disableInitializers` in its constructor to prevent
/// initialization of the implementation contract itself.
///
/// Security:
/// - Only the gateway can mint and burn. Standard ERC20 transfers and approvals are
/// unrestricted.
/// - The gateway address and decimals are set once during initialization and cannot
/// be changed.
contract LighterWrappedERC20V1 is ERC20PermitUpgradeable {
  /// @custom:storage-location erc7201:lighter.storage.LighterWrappedERC20V1Storage
  struct LighterWrappedERC20V1Storage {
    /// @dev The gateway that deployed and initialized this proxy. Sole mint/burn authority.
    address gateway;
    /// @dev Token decimals, mirroring the canonical token on the source chain.
    uint8 tokenDecimals;
  }

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.LighterWrappedERC20V1Storage")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant LighterWrappedERC20V1StorageLocation = 0xe1650a90870a321ba5cd0f4b176d767fb348074ace4b073cbbe657cad1fdfd00;

  error LighterWrappedERC20V1_OnlyGateway();

  modifier onlyGateway() {
    if (msg.sender != _getStorage().gateway) revert LighterWrappedERC20V1_OnlyGateway();
    _;
  }

  /// @dev Prevent initialization of the implementation contract itself.
  /// Only BeaconProxy instances should be initialized.
  constructor() {
    _disableInitializers();
  }

  /// @notice Initialize the wrapped token. Can only be called once (enforced by `initializer`).
  /// The caller becomes the gateway with exclusive mint/burn authority.
  /// @param name_ Token name, typically mirrored from the canonical token on the source chain.
  /// @param symbol_ Token symbol, typically mirrored from the canonical token on the source chain.
  /// @param decimals_ Token decimals, mirrored from the canonical token on the source chain.
  function initialize(string memory name_, string memory symbol_, uint8 decimals_) external initializer {
    __ERC20_init(name_, symbol_);
    __ERC20Permit_init(name_);
    LighterWrappedERC20V1Storage storage $ = _getStorage();
    $.tokenDecimals = decimals_;
    $.gateway = msg.sender;
  }

  /// @notice The gateway that deployed and initialized this proxy. Sole mint/burn authority.
  function gateway() public view returns (address) {
    return _getStorage().gateway;
  }

  /// @notice Returns the number of decimals for this token.
  /// @dev Overrides ERC20Upgradeable's default of 18 to return the value set during initialization.
  function decimals() public view override returns (uint8) {
    return _getStorage().tokenDecimals;
  }

  /// @notice Mint tokens to an address. Only callable by the gateway.
  /// @param to Recipient of the minted tokens.
  /// @param amount Amount to mint.
  function externalMint(address to, uint256 amount) external onlyGateway {
    _mint(to, amount);
  }

  /// @notice Burn tokens from the caller (gateway). Only callable by the gateway.
  /// @param amount Amount to burn.
  function externalBurn(uint256 amount) external onlyGateway {
    _burn(msg.sender, amount);
  }

  /// @dev Derives the EIP-712 domain name from the ERC20 token name.
  function _EIP712Name() internal view override returns (string memory) {
    return name();
  }

  /// @dev EIP-2612 domain version.
  function _EIP712Version() internal pure override returns (string memory) {
    return "1";
  }

  /// @dev Returns a pointer to the ERC-7201 namespaced storage struct.
  /// @return $ The storage pointer.
  function _getStorage() private pure returns (LighterWrappedERC20V1Storage storage $) {
    assembly {
      $.slot := LighterWrappedERC20V1StorageLocation
    }
  }
}
