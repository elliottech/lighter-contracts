// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

/// @title zkLighter DesertVerifier Interface
/// @author zkLighter Team
interface IDesertVerifier {
  /// @notice Verifies a SNARK proof for the desert mode
  /// @param proof The SNARK proof to verify
  /// @param public_inputs The public inputs for the proof
  /// @return success True if the proof is valid, false otherwise
  function Verify(bytes calldata proof, uint256[] calldata public_inputs) external view returns (bool success);
}
