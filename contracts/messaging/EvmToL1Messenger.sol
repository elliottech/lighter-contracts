// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Burner} from "../Burner.sol";
import {EVM_INTEROP_MANAGER_ADDR} from "../Constants.sol";

enum WithdrawalKind {
  User,
  SendTokenInfo
}

/// @notice The entrypoint for passing messages from EVM to L1
contract EvmToL1Messenger {
  event WithdrawalInitiated(address indexed sender, address indexed to, uint256 value, uint256 nonce, WithdrawalKind kind, bytes data);

  error EvmToL1Messenger_OnlyEvmInteropManager();

  /// @notice Extra gas burned in `sendTokenInfo` to reflect the post-state read
  /// of `TOKEN_ADMIN_SLOT` on the target token that the chain's state transition
  /// function performs outside the EVM. That read is invisible to the EVM gas
  /// meter, so we anchor the surcharge on the EVM cold-SLOAD price.
  uint256 internal constant COLD_SLOAD_GAS = 2100;

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.EvmToL1MessengerStorage")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant EvmToL1MessengerStorageLocation = 0x516f6562cf50bfe61c45fb8b6e98e02e3b0549fea66fc2ca1de7f268c18e2a00;

  function _getEvmToL1MessengerStorage() private pure returns (EvmToL1MessengerStorage storage $) {
    assembly {
      $.slot := EvmToL1MessengerStorageLocation
    }
  }

  struct EvmToL1MessengerStorage {
    uint256 msgNonce;
  }

  modifier onlyEvmInteropManager() {
    if (msg.sender != EVM_INTEROP_MANAGER_ADDR) revert EvmToL1Messenger_OnlyEvmInteropManager();
    _;
  }

  function initiateWithdrawal(address _target, bytes memory _data) public payable {
    EvmToL1MessengerStorage storage $ = _getEvmToL1MessengerStorage();

    emit WithdrawalInitiated(msg.sender, _target, msg.value, $.msgNonce, WithdrawalKind.User, _data);

    unchecked {
      $.msgNonce++;
    }

    if (msg.value != 0) burn();
  }

  /// @notice Send EVM token info (admin slot + metadata) to L1. The chain's
  /// state transition function will replace the bytes32(0) placeholder in
  /// `_data` with the actual TOKEN_ADMIN_SLOT value from the target token.
  /// @param _target The L1 target contract.
  /// @param _data The calldata with a bytes32(0) placeholder for the slot value.
  function sendTokenInfo(address _target, bytes memory _data) public onlyEvmInteropManager {
    EvmToL1MessengerStorage storage $ = _getEvmToL1MessengerStorage();

    emit WithdrawalInitiated(msg.sender, _target, 0, $.msgNonce, WithdrawalKind.SendTokenInfo, _data);

    unchecked {
      $.msgNonce++;
    }

    _consumeGas(COLD_SLOAD_GAS);
  }

  /// @dev Spin until at least `amount` gas has been consumed. Used to charge
  /// for state transition work outside the EVM that the EVM gas meter does not see.
  function _consumeGas(uint256 amount) private view {
    uint256 target = gasleft() - amount;
    while (gasleft() > target) {}
  }

  /// @dev This function is public in case somebody self-destruct donates.
  function burn() public {
    new Burner{value: address(this).balance}();
  }

  receive() external payable {
    initiateWithdrawal(msg.sender, hex"");
  }

  function msgNonce() external view returns (uint256) {
    EvmToL1MessengerStorage storage $ = _getEvmToL1MessengerStorage();
    return $.msgNonce;
  }
}
