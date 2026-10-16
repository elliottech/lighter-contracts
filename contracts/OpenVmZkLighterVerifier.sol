// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import {IOpenVmZkLighterVerifier} from "./interfaces/IOpenVmZkLighterVerifier.sol";
import {IOpenVmHalo2Verifier} from "openvm-solidity-sdk/v2.0-deferral/interfaces/IOpenVmHalo2Verifier.sol";

/// @title OpenVmZkLighterVerifier
contract OpenVmZkLighterVerifier is IOpenVmZkLighterVerifier {
  /// @notice The OpenVM SDK Halo2 verifier that this adapter wraps.
  IOpenVmHalo2Verifier public immutable openVmVerifier;
  /// @notice Pinned final-agg program exe commitment the proof must attest to.
  bytes32 public immutable appExeCommit;
  /// @notice Pinned final-agg program VM commitment the proof must attest to.
  bytes32 public immutable appVmCommit;

  constructor(address _openVmVerifier, bytes32 _appExeCommit, bytes32 _appVmCommit) {
    openVmVerifier = IOpenVmHalo2Verifier(_openVmVerifier);
    appExeCommit = _appExeCommit;
    appVmCommit = _appVmCommit;
  }

  // ------ UPGRADEABLE START ------
  function initialize(bytes calldata) external {}

  /// @notice Verifier contract upgrade. Can be external because Proxy contract intercepts illegal calls of this function.
  /// @param upgradeParameters Encoded representation of upgrade parameters
  function upgrade(bytes calldata upgradeParameters) external {}

  // ------ UPGRADEABLE END ------

  /// @inheritdoc IOpenVmZkLighterVerifier
  /// @param proof The OpenVM `EvmProof` data (`abi.encodePacked(accumulator, proofSuffix)`).
  /// @param commitment The 32-byte batch commitment, forwarded as the OpenVM public values.
  function verify(bytes calldata proof, bytes32 commitment) external view returns (bool success) {
    openVmVerifier.verify({publicValues: abi.encodePacked(commitment), proofData: proof, appExeCommit: appExeCommit, appVmCommit: appVmCommit});
    return true;
  }
}
