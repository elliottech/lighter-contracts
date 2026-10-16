// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IMintGateway} from "../interfaces/IMintGateway.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

enum CanonicalDomain {
  None,
  L1,
  Core,
  EVM
}

library TokenInteropLib {
  error TokenInteropLib_AssetNotActive();
  error TokenInteropLib_RecipientAddressInvalid();
  error TokenInteropLib_AmountMismatch();
  error TokenInteropLib_InvalidDepositAmount();
  error TokenInteropLib_InsufficientMsgValue();

  /// @notice Pull ERC20 tokens from sender. Only called for non-native assets.
  /// @param localToken ERC20 token address on this domain.
  /// @param amount Amount to pull (in token units).
  /// @param isCanonicalLocal True when this domain is the canonical domain of the asset.
  function transferIn(address localToken, address localGateway, uint256 amount, bool isCanonicalLocal) internal {
    if (isCanonicalLocal) {
      IERC20 token = IERC20(localToken);

      // Pull tokens to the escrow destination:
      // - If gateway selected: tokens go to escrow gateway
      // - If no gateway yet: tokens stay in the interop manager (acts as escrow pre-selection)
      address escrowDest = localGateway != address(0) ? localGateway : address(this);

      uint256 balanceBefore = token.balanceOf(escrowDest);
      SafeERC20.safeTransferFrom(token, msg.sender, escrowDest, amount);
      uint256 balanceAfter = token.balanceOf(escrowDest);
      if (balanceAfter != balanceBefore + amount) revert TokenInteropLib_AmountMismatch();
    } else {
      assert(localGateway != address(0));
      // Transfer wrapper tokens to the gateway, then have the gateway burn them
      IERC20 token = IERC20(localToken);

      uint256 balanceBefore = token.balanceOf(localGateway);
      SafeERC20.safeTransferFrom(token, msg.sender, localGateway, amount);
      uint256 balanceAfter = token.balanceOf(localGateway);
      if (balanceAfter != balanceBefore + amount) revert TokenInteropLib_AmountMismatch();

      IMintGateway(localGateway).managerBurn(localToken, amount);
    }
  }

  /// @dev Cached creation code for BeaconProxy — avoids re-reading bytecode on every call.
  bytes private constant BEACON_PROXY_CREATION_CODE = type(BeaconProxy).creationCode;

  function computeCreate2Wrapper(address mintGateway, bytes32 salt) internal pure returns (address) {
    bytes32 initCodeHash = keccak256(abi.encodePacked(BEACON_PROXY_CREATION_CODE, abi.encode(mintGateway, "")));
    return Create2.computeAddress(salt, initCodeHash, mintGateway);
  }

  function toBaseAmount(uint256 amount, uint128 tickSize) internal pure returns (uint64) {
    return SafeCast.toUint64(amount / tickSize);
  }

  function fetchMetadata(address token) internal view returns (string memory name, string memory symbol, uint8 decimals) {
    decimals = 18;

    try IERC20Metadata(token).name() returns (string memory n) {
      name = n;
    } catch {}

    try IERC20Metadata(token).symbol() returns (string memory s) {
      symbol = s;
    } catch {}

    try IERC20Metadata(token).decimals() returns (uint8 d) {
      decimals = d;
    } catch {}
  }
}
