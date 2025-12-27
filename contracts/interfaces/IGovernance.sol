// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title zkLighter Events Interface
/// @author zkLighter Team
interface IGovernance {
  /// @notice Governor changed
  event NewGovernor(address newGovernor);

  /// @notice Validator status changed
  event ValidatorStatusUpdate(address validatorAddress, bool isActive);

  /// @notice Thrown in constructor when USDC is not a contract or zero address
  error ZkLighter_Governance_InvalidUSDCAddress();

  /// @notice Thrown in constructor when Governor Address is zero
  error ZkLighter_Governance_GovernorCannotBeZero();

  ///@notice Thrown by requireGovernor function and when the address is not a governor
  error ZkLighter_Governance_OnlyGovernor();

  /// @notice Thrown when the validator address is zero
  error ZkLighter_Governance_ValidatorCannotBeZero();

  /// @notice Thrown when the validator address is invalid
  error ZkLighter_Governance_InvalidValidator();

  /// @notice Change current governor
  /// @param _newGovernor Address of the new governor
  function changeGovernor(address _newGovernor) external;

  /// @return The address of the USDC address
  function usdc() external view returns (IERC20);

  /// @notice Check if specified address is governor
  /// @param _address Address to check
  function requireGovernor(address _address) external view;

  /// @notice Set validator address
  /// @param _validator Address of the validator
  /// @param _active Validator status
  function setValidator(address _validator, bool _active) external;

  /// @notice Check if specified address is validator
  /// @param _address Address to check
  function isActiveValidator(address _address) external view;
}
