// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/// @title zkLighter Emergency Pause Contract
/// @author zkLighter Team
abstract contract EmergencyPause {
  enum PauseTier {
    PauseGuardian,
    EmergencyGuardian
  }

  struct PauseState {
    uint64 startedAt;
    uint64 expiresAt;
    uint64 cooldownEndsAt;
  }

  /// @custom:storage-location erc7201:zklighter.storage.EmergencyPause
  struct EmergencyPauseStorage {
    address pauseGuardian;
    address emergencyGuardian;
    PauseState pauseGuardianState;
    PauseState emergencyGuardianState;
  }

  // keccak256(abi.encode(uint256(keccak256("zklighter.storage.EmergencyPause")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 internal constant EMERGENCY_PAUSE_STORAGE_LOCATION = 0x48e77f48bcec852db4f14007725dea1c391e1f193bc893e97e7b067e5ea1ab00;

  uint64 public constant PAUSE_GUARDIAN_MIN_DURATION = 2 hours;
  uint64 public constant PAUSE_GUARDIAN_MAX_DURATION = 24 hours;
  uint64 public constant PAUSE_GUARDIAN_COOLDOWN = 24 hours;

  uint64 public constant EMERGENCY_GUARDIAN_MIN_DURATION = 24 hours;
  uint64 public constant EMERGENCY_GUARDIAN_MAX_DURATION = 72 hours;
  uint64 public constant EMERGENCY_GUARDIAN_COOLDOWN = 7 days;

  event PauseGuardianChanged(address indexed oldGuardian, address indexed newGuardian);

  event EmergencyGuardianChanged(address indexed oldGuardian, address indexed newGuardian);

  event PauseStarted(PauseTier indexed tier, address indexed guardian, uint64 startedAt, uint64 expiresAt, uint64 cooldownEndsAt);

  event PauseExtended(PauseTier indexed tier, address indexed guardian, uint64 startedAt, uint64 expiresAt, uint64 cooldownEndsAt);

  event PauseEnded(PauseTier indexed tier, address indexed actor, uint64 cooldownEndsAt);

  error NotPauseGuardian();
  error NotEmergencyGuardian();
  error Paused();
  error AlreadyPaused();
  error NotPaused();
  error PauseCooldownActive();
  error InvalidPauseDuration();
  error MinimumPauseDurationNotElapsed();

  modifier onlyGovernor() virtual;

  modifier onlyPauseGuardian() {
    if (msg.sender != _emergencyPauseStorage().pauseGuardian) revert NotPauseGuardian();
    _;
  }

  modifier onlyEmergencyGuardian() {
    if (msg.sender != _emergencyPauseStorage().emergencyGuardian) revert NotEmergencyGuardian();
    _;
  }

  function _emergencyPauseStorage() internal pure returns (EmergencyPauseStorage storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := EMERGENCY_PAUSE_STORAGE_LOCATION
    }
  }

  /// @notice Governance may change the Pause Guardian at any time.
  function setPauseGuardian(address newPauseGuardian) external onlyGovernor {
    EmergencyPauseStorage storage $ = _emergencyPauseStorage();
    address oldPauseGuardian = $.pauseGuardian;
    $.pauseGuardian = newPauseGuardian;

    emit PauseGuardianChanged(oldPauseGuardian, newPauseGuardian);
  }

  /// @notice Governance may change the Emergency Guardian at any time.
  function setEmergencyGuardian(address newEmergencyGuardian) external onlyGovernor {
    EmergencyPauseStorage storage $ = _emergencyPauseStorage();
    address oldEmergencyGuardian = $.emergencyGuardian;
    $.emergencyGuardian = newEmergencyGuardian;

    emit EmergencyGuardianChanged(oldEmergencyGuardian, newEmergencyGuardian);
  }

  /// @notice Short operational pause of commit/verify/execute and withdrawals.
  function pauseSystem(uint64 duration) external onlyPauseGuardian {
    _startPause(
      PauseTier.PauseGuardian,
      _emergencyPauseStorage().pauseGuardianState,
      PAUSE_GUARDIAN_MIN_DURATION,
      PAUSE_GUARDIAN_MAX_DURATION,
      PAUSE_GUARDIAN_COOLDOWN,
      duration
    );
  }

  /// @notice Longer emergency pause of commit/verify/execute and withdrawals.
  function emergencyPauseSystem(uint64 duration) external onlyEmergencyGuardian {
    _startPause(
      PauseTier.EmergencyGuardian,
      _emergencyPauseStorage().emergencyGuardianState,
      EMERGENCY_GUARDIAN_MIN_DURATION,
      EMERGENCY_GUARDIAN_MAX_DURATION,
      EMERGENCY_GUARDIAN_COOLDOWN,
      duration
    );
  }

  /// @notice Pause Guardian may extend its pause before it expires, but not beyond the maximum duration.
  /// @dev The cooldown is recomputed from the new expiry.
  function extendPauseGuardianPause(uint64 newExpiresAt) external onlyPauseGuardian {
    _extendPauseUntil(
      PauseTier.PauseGuardian,
      _emergencyPauseStorage().pauseGuardianState,
      PAUSE_GUARDIAN_MAX_DURATION,
      PAUSE_GUARDIAN_COOLDOWN,
      newExpiresAt
    );
  }

  /// @notice Emergency Guardian may extend its pause before it expires, but not beyond the maximum duration.
  /// @dev The cooldown is recomputed from the new expiry.
  function extendEmergencyPause(uint64 newExpiresAt) external onlyEmergencyGuardian {
    _extendPauseUntil(
      PauseTier.EmergencyGuardian,
      _emergencyPauseStorage().emergencyGuardianState,
      EMERGENCY_GUARDIAN_MAX_DURATION,
      EMERGENCY_GUARDIAN_COOLDOWN,
      newExpiresAt
    );
  }

  /// @notice Governance may unpause the Pause Guardian pause after the minimum duration.
  function unpauseSystem() external onlyGovernor {
    _endPause(PauseTier.PauseGuardian, _emergencyPauseStorage().pauseGuardianState, PAUSE_GUARDIAN_MIN_DURATION, PAUSE_GUARDIAN_COOLDOWN);
  }

  /// @notice Governance may unpause the Emergency Guardian pause after the minimum duration.
  function emergencyUnpauseSystem() external onlyGovernor {
    _endPause(
      PauseTier.EmergencyGuardian,
      _emergencyPauseStorage().emergencyGuardianState,
      EMERGENCY_GUARDIAN_MIN_DURATION,
      EMERGENCY_GUARDIAN_COOLDOWN
    );
  }

  function pauseGuardian() public view returns (address) {
    return _emergencyPauseStorage().pauseGuardian;
  }

  function emergencyGuardian() public view returns (address) {
    return _emergencyPauseStorage().emergencyGuardian;
  }

  function pauseGuardianState() public view returns (uint64 startedAt, uint64 expiresAt, uint64 cooldownEndsAt) {
    PauseState storage state = _emergencyPauseStorage().pauseGuardianState;
    return (state.startedAt, state.expiresAt, state.cooldownEndsAt);
  }

  function emergencyGuardianState() public view returns (uint64 startedAt, uint64 expiresAt, uint64 cooldownEndsAt) {
    PauseState storage state = _emergencyPauseStorage().emergencyGuardianState;
    return (state.startedAt, state.expiresAt, state.cooldownEndsAt);
  }

  function pauseGuardianPaused() public view returns (bool) {
    return _paused(_emergencyPauseStorage().pauseGuardianState);
  }

  function emergencyGuardianPaused() public view returns (bool) {
    return _paused(_emergencyPauseStorage().emergencyGuardianState);
  }

  function _startPause(PauseTier tier, PauseState storage state, uint64 minDuration, uint64 maxDuration, uint64 cooldown, uint64 duration) internal {
    if (_paused(state)) revert AlreadyPaused();
    if (block.timestamp < state.cooldownEndsAt) revert PauseCooldownActive();

    if (duration < minDuration || duration > maxDuration) {
      revert InvalidPauseDuration();
    }

    uint64 startedAt = uint64(block.timestamp);
    uint64 expiresAt = startedAt + duration;
    uint64 cooldownEndsAt = expiresAt + cooldown;

    state.startedAt = startedAt;
    state.expiresAt = expiresAt;
    state.cooldownEndsAt = cooldownEndsAt;

    emit PauseStarted(tier, msg.sender, startedAt, expiresAt, cooldownEndsAt);
  }

  function _extendPauseUntil(PauseTier tier, PauseState storage state, uint64 maxDuration, uint64 cooldown, uint64 newExpiresAt) internal {
    if (!_paused(state)) revert NotPaused();

    uint64 maxExpiresAt = state.startedAt + maxDuration;

    if (newExpiresAt <= state.expiresAt || newExpiresAt > maxExpiresAt) {
      revert InvalidPauseDuration();
    }

    state.expiresAt = newExpiresAt;
    state.cooldownEndsAt = newExpiresAt + cooldown;

    emit PauseExtended(tier, msg.sender, state.startedAt, newExpiresAt, state.cooldownEndsAt);
  }

  function _endPause(PauseTier tier, PauseState storage state, uint64 minDuration, uint64 cooldown) internal {
    if (!_paused(state)) revert NotPaused();

    if (block.timestamp < state.startedAt + minDuration) {
      revert MinimumPauseDurationNotElapsed();
    }

    uint64 cooldownEndsAt = uint64(block.timestamp) + cooldown;

    state.expiresAt = 0;
    state.cooldownEndsAt = cooldownEndsAt;

    emit PauseEnded(tier, msg.sender, cooldownEndsAt);
  }

  function _paused(PauseState storage state) internal view returns (bool) {
    return block.timestamp < state.expiresAt;
  }
}
