// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.25;

/// @dev Calldata decoding helpers for fixed-width unsigned integers.
/// Each function reads at byte offset `o` within `data` and returns the value
/// encoded in the first N bytes starting at that offset.
/// No length checks are performed: if `o + N > data.length`, the read will
/// succeed and return whatever calldata follows `data` (only bytes past the
/// end of calldata read as zero). Callers should validate bounds when strict
/// decoding is required.
library Bytes {
  function unsafeReadU8At(bytes calldata data, uint256 o) internal pure returns (uint8 v) {
    /// @solidity memory-safe-assembly
    assembly {
      v := shr(0xf8, calldataload(add(data.offset, o)))
    }
  }

  function unsafeReadU16At(bytes calldata data, uint256 o) internal pure returns (uint16 v) {
    /// @solidity memory-safe-assembly
    assembly {
      v := shr(0xf0, calldataload(add(data.offset, o)))
    }
  }

  function unsafeReadU24At(bytes calldata data, uint256 o) internal pure returns (uint24 v) {
    /// @solidity memory-safe-assembly
    assembly {
      v := shr(0xe8, calldataload(add(data.offset, o)))
    }
  }

  function unsafeReadU32At(bytes calldata data, uint256 o) internal pure returns (uint32 v) {
    /// @solidity memory-safe-assembly
    assembly {
      v := shr(0xe0, calldataload(add(data.offset, o)))
    }
  }

  function unsafeReadU48At(bytes calldata data, uint256 o) internal pure returns (uint48 v) {
    /// @solidity memory-safe-assembly
    assembly {
      v := shr(0xd0, calldataload(add(data.offset, o)))
    }
  }

  function unsafeReadU56At(bytes calldata data, uint256 o) internal pure returns (uint56 v) {
    /// @solidity memory-safe-assembly
    assembly {
      v := shr(0xc8, calldataload(add(data.offset, o)))
    }
  }

  function unsafeReadU64At(bytes calldata data, uint256 o) internal pure returns (uint64 v) {
    /// @solidity memory-safe-assembly
    assembly {
      v := shr(0xc0, calldataload(add(data.offset, o)))
    }
  }

  function unsafeReadAddressAt(bytes calldata data, uint256 o) internal pure returns (address v) {
    /// @solidity memory-safe-assembly
    assembly {
      v := shr(0x60, calldataload(add(data.offset, o)))
    }
  }

  function unsafeReadBytes32At(bytes calldata data, uint256 o) internal pure returns (bytes32 v) {
    /// @solidity memory-safe-assembly
    assembly {
      v := calldataload(add(data.offset, o))
    }
  }
}
