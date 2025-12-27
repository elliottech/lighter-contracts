// SPDX-License-Identifier: Apache-2.0

pragma solidity 0.8.25;

/// @title zkLighter Bytes Library
/// @notice Implements helper functions to read bytes and convert them to other types
/// @author zkLighter Team
library Bytes {
  /// @dev Theoretically possible overflow of (_start + 0x8)
  function bytesToUInt64(bytes memory _bytes, uint256 _start) internal pure returns (uint64 r) {
    uint256 offset = _start + 0x8;
    require(_bytes.length >= offset, "S");
    assembly {
      r := mload(add(_bytes, offset))
    }
  }

  /// @dev Theoretically possible overflow of (_start + 0x6)
  function bytesToUInt48(bytes memory _bytes, uint256 _start) internal pure returns (uint48 r) {
    uint256 offset = _start + 0x6;
    require(_bytes.length >= offset, "S");
    assembly {
      r := mload(add(_bytes, offset))
    }
  }

  /// @dev Theoretically possible overflow of (_offset + 0x8)
  function readUInt64(bytes memory _data, uint256 _offset) internal pure returns (uint256 newOffset, uint64 r) {
    newOffset = _offset + 8;
    r = bytesToUInt64(_data, _offset);
  }

  /// @dev Theoretically possible overflow of (_offset + 0x6)
  function readUInt48(bytes memory _data, uint256 _offset) internal pure returns (uint256 newOffset, uint48 r) {
    newOffset = _offset + 6;
    r = bytesToUInt48(_data, _offset);
  }

  /// @dev Theoretically possible overflow of (_offset + 0x1)
  function readUInt8(bytes memory _data, uint256 _offset) internal pure returns (uint256 newOffset, uint8 r) {
    newOffset = _offset + 1;
    r = uint8(_data[_offset]);
  }
}
