// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {LIGHTER_WRAPPED_ERC20_V1} from "../../Constants.sol";
import {LighterWrappedERC20V1} from "../../token/LighterWrappedERC20V1.sol";

/// @notice Construction-only initializer for the USDC wrapper's TransparentProxy.
/// @dev Initializes through the shared ERC-20 predeploy, seeds the ownership-proof
/// slot, and replaces itself as implementation before the proxy constructor returns.
contract UsdcWrapperBootstrap {
  bytes32 private constant TOKEN_ADMIN_SLOT = keccak256("lighter.admin.slot");
  // bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
  bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
  address private immutable SELF = address(this);

  event Upgraded(address indexed implementation);

  error UsdcWrapperBootstrap_InvalidContext();
  error UsdcWrapperBootstrap_InvalidTokenAdmin();
  error UsdcWrapperBootstrap_MissingImplementation();

  function initialize(address tokenAdmin) external {
    address initialImplementation;
    assembly {
      initialImplementation := sload(IMPLEMENTATION_SLOT)
    }
    // This must be being called from the TransparentProxy constructor
    if (address(this).code.length != 0 || initialImplementation != SELF) revert UsdcWrapperBootstrap_InvalidContext();
    if (tokenAdmin == address(0)) revert UsdcWrapperBootstrap_InvalidTokenAdmin();
    address implementation = LIGHTER_WRAPPED_ERC20_V1;
    if (implementation.code.length == 0) revert UsdcWrapperBootstrap_MissingImplementation();

    // Preserve the deploying gateway as msg.sender and initialize the predeploy's
    // exact storage layout, without sharing Initializable state with this bootstrap.
    (bool success, bytes memory returndata) = implementation.delegatecall(
      abi.encodeCall(LighterWrappedERC20V1.initialize, ("Bridged USDC", "wUSDC", 6))
    );
    if (!success) {
      assembly {
        revert(add(returndata, 32), mload(returndata))
      }
    }

    bytes32 tokenAdminSlot = TOKEN_ADMIN_SLOT;
    assembly {
      sstore(tokenAdminSlot, tokenAdmin)
      sstore(IMPLEMENTATION_SLOT, implementation)
    }

    emit Upgraded(implementation);
  }
}
