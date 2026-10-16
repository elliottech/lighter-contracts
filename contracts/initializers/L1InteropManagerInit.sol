// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {L1InteropManager} from "../interop/L1InteropManager.sol";
import {CanonicalDomain} from "../interop/TokenInteropLib.sol";
import {IGovernance} from "../interfaces/IGovernance.sol";
import {IL1CoreMessaging} from "../interfaces/IL1CoreMessaging.sol";
import {IZkLighter} from "../interfaces/IZkLighter.sol";

/// @dev L1InteropManager with an initializer for fresh deployments (e.g. devnet).
contract L1InteropManagerInit is L1InteropManager {
  constructor(
    IZkLighter _zkLighter,
    IL1CoreMessaging _l1CoreMessaging,
    address _evmInteropManager,
    address _defaultL1MintGateway,
    address _defaultEvmMintGateway,
    address _defaultL1EscrowGateway,
    address _defaultEvmEscrowGateway
  )
    L1InteropManager(
      _zkLighter,
      _l1CoreMessaging,
      _evmInteropManager,
      _defaultL1MintGateway,
      _defaultEvmMintGateway,
      _defaultL1EscrowGateway,
      _defaultEvmEscrowGateway
    )
  {}

  function initialize(bytes calldata data) external initializer {
    IGovernance governance = abi.decode(data, (IGovernance));
    L1InteropManagerStorage storage $ = _getL1InteropManagerStorage();
    $.governance = governance;
    $.assetConfigs[NATIVE_ASSET_INDEX] = CoreAssetL1Config({
      canonicalDomain: CanonicalDomain.L1,
      l1Token: ETH_ADDRESS,
      coreTokenAdmin: address(0),
      extensionMultiplier: ETH_EXTENSION_MULTIPLIER,
      tickSize: ETH_TICK_SIZE,
      l1Gateway: address(0)
    });
    $.l1TokenToAssetIndex[ETH_ADDRESS] = NATIVE_ASSET_INDEX;
  }
}
