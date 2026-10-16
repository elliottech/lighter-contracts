// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

/// @title OpenVM zkLighter Verifier Interface
/// @author zkLighter Team
interface IOpenVmZkLighterVerifier {
  /// @notice Verifies an OpenVM SNARK proof
  /// @param proof The SNARK proof to verify
  /// @param commitment The 32-byte batch commitment the proof must attest to
  /// @return success True if the proof is valid, false otherwise
  function verify(bytes calldata proof, bytes32 commitment) external view returns (bool success);
}
