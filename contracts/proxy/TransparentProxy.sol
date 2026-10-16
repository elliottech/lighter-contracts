// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @title TransparentProxy
/// @notice Vendored from Optimism's Proxy.sol
///         (https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts-bedrock/src/universal/Proxy.sol)
///         with the following modifications:
///         - Solidity version bumped to 0.8.25
///         - Constants library dependency removed; slot constant inlined
///         - Admin hardcoded to address(0);
///           all admin management (changeAdmin, admin(), storage slot) removed
///         - `upgradeTo` removed; only `upgradeToAndCall` retained
contract TransparentProxy {
  /// @notice The EIP-1967 implementation storage slot.
  ///         Derived as: bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
  ///         The subtraction of 1 ensures the slot has no known preimage, preventing
  ///         accidental collisions with Solidity's standard storage layout.
  bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

  /// @notice Emitted each time the implementation is changed (EIP-1967).
  /// @param implementation The address of the new implementation contract.
  event Upgraded(address indexed implementation);

  /// @notice Routes non-admin callers to the implementation via delegatecall.
  ///         Only address(0) can reach the admin body.
  modifier proxyCallIfNotAdmin() {
    if (msg.sender == address(0)) {
      _;
    } else {
      // This WILL halt the call frame on completion.
      _doProxyCall();
    }
  }

  /// @notice Sets the initial implementation during contract deployment.
  /// @param _implementation Address of the initial implementation contract.
  /// @param _data           Optional calldata to delegatecall the implementation with.
  constructor(address _implementation, bytes memory _data) {
    _setImplementation(_implementation);
    if (_data.length > 0) {
      (bool success, ) = _implementation.delegatecall(_data);
      require(success, "Proxy: delegatecall to new implementation contract failed");
    }
  }

  receive() external payable {
    _doProxyCall();
  }

  fallback() external payable {
    _doProxyCall();
  }

  /// @notice Set the implementation and call a function in a single transaction.
  ///         Useful to ensure atomic execution of initialization-based upgrades.
  /// @param _implementation Address of the implementation contract.
  /// @param _data           Calldata to delegatecall the new implementation with.
  function upgradeToAndCall(address _implementation, bytes calldata _data) public payable virtual proxyCallIfNotAdmin returns (bytes memory) {
    _setImplementation(_implementation);
    if (_data.length > 0) {
      (bool success, bytes memory returndata) = _implementation.delegatecall(_data);
      require(success, "Proxy: delegatecall to new implementation contract failed");
      return returndata;
    }
    return "";
  }

  /// @notice Queries the implementation address. Only callable via eth_call (msg.sender == 0).
  /// @return Implementation address.
  function implementation() public virtual proxyCallIfNotAdmin returns (address) {
    return _getImplementation();
  }

  /// @notice Writes the implementation address to the EIP-1967 slot.
  /// @param _implementation New implementation address.
  function _setImplementation(address _implementation) internal {
    assembly {
      sstore(IMPLEMENTATION_SLOT, _implementation)
    }
    emit Upgraded(_implementation);
  }

  /// @notice Performs the proxy call via a delegatecall.
  function _doProxyCall() internal {
    address impl = _getImplementation();
    require(impl != address(0), "Proxy: implementation not initialized");

    assembly {
      calldatacopy(0x0, 0x0, calldatasize())
      let success := delegatecall(gas(), impl, 0x0, calldatasize(), 0x0, 0x0)
      returndatacopy(0x0, 0x0, returndatasize())
      if iszero(success) {
        revert(0x0, returndatasize())
      }
      return(0x0, returndatasize())
    }
  }

  /// @notice Reads the implementation address from the EIP-1967 slot.
  /// @return impl Implementation address.
  function _getImplementation() internal view returns (address impl) {
    assembly {
      impl := sload(IMPLEMENTATION_SLOT)
    }
  }
}
