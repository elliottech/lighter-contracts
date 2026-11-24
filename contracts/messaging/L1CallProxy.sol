// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Executes authenticated L2-to-L1 calls without exposing ZkLighter's
/// token-vault identity to arbitrary targets.
contract L1CallProxy {
  address public immutable ZK_LIGHTER;

  error L1CallProxy_InvalidZkLighter();
  error L1CallProxy_OnlyZkLighter();

  constructor(address zkLighter) {
    if (zkLighter == address(0)) revert L1CallProxy_InvalidZkLighter();
    ZK_LIGHTER = zkLighter;
  }

  function execute(address target, bytes calldata data) external payable {
    if (msg.sender != ZK_LIGHTER) revert L1CallProxy_OnlyZkLighter();

    (bool success, ) = target.call{value: msg.value}(data);
    if (!success) {
      /// @solidity memory-safe-assembly
      assembly {
        let ptr := mload(0x40)
        returndatacopy(ptr, 0, returndatasize())
        revert(ptr, returndatasize())
      }
    }
  }
}
