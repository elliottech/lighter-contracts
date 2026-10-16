// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IGovernance.sol";
import "./Config.sol";

/// @title zkLighter Governance Contract
/// @author zkLighter Team
contract Governance is IGovernance, Config, Initializable, ReentrancyGuardUpgradeable {
  /// @notice USDC is the only allowed asset to be deposited, which increases collateral.
  IERC20 public usdc;

  /// @notice Governor address
  address public networkGovernor;

  /// @notice Validators
  mapping(address => bool) public validators;

  // OpenZeppelin Contracts (last updated v4.9.0) (proxy/utils/Initializable.sol)
  // * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure */
  // * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity. */
  // * Avoid leaving a contract uninitialized. */
  // * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation */
  // * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke */
  // * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed: */
  constructor() {
    _disableInitializers();
  }

  /// @notice Governance contract initialization
  /// @param initializationParameters Encoded representation of initialization parameters:
  ///     _networkGovernor The address of network governor
  ///     _usdcAddress The address of USDC contract
  function initialize(bytes calldata initializationParameters) external initializer {
    __ReentrancyGuard_init();

    (address _networkGovernor, address _usdcAddress) = abi.decode(initializationParameters, (address, address));

    if (_networkGovernor == address(0)) {
      revert ZkLighter_Governance_GovernorCannotBeZero();
    }

    if (_usdcAddress == address(0)) {
      revert ZkLighter_Governance_InvalidUSDCAddress();
    }

    networkGovernor = _networkGovernor;
    emit NewGovernor(_networkGovernor);

    usdc = IERC20(_usdcAddress);
  }

  /// @notice Governance contract upgrade. Can be external because Proxy contract intercepts illegal calls of this function
  /// @param upgradeParameters Encoded representation of upgrade parameters
  // solhint-disable-next-line no-empty-blocks
  function upgrade(bytes calldata upgradeParameters) external {}

  /// @notice Change current governor
  /// @param _newGovernor Address of the new governor
  function changeGovernor(address _newGovernor) external nonReentrant onlyGovernor {
    if (_newGovernor == address(0)) {
      revert ZkLighter_Governance_GovernorCannotBeZero();
    }
    if (networkGovernor != _newGovernor) {
      networkGovernor = _newGovernor;
      emit NewGovernor(_newGovernor);
    }
  }

  /// @notice Check if specified address is the governor
  /// @param _address Address to check
  function requireGovernor(address _address) public view {
    // Only by governor
    if (_address != networkGovernor) {
      revert ZkLighter_Governance_OnlyGovernor();
    }
  }

  /// @notice Check if specified address is the governor
  modifier onlyGovernor() {
    requireGovernor(msg.sender);
    _;
  }

  function setValidator(address _validator, bool _active) external nonReentrant onlyGovernor {
    if (_validator == address(0)) {
      revert ZkLighter_Governance_ValidatorCannotBeZero();
    }
    if (validators[_validator] != _active) {
      validators[_validator] = _active;
      emit ValidatorStatusUpdate(_validator, _active);
    }
  }

  function isActiveValidator(address _address) external view {
    if (!validators[_address]) {
      revert ZkLighter_Governance_InvalidValidator();
    }
  }
}
