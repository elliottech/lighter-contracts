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

  // NOTE: theoretically possible overflow of (_start + 0x7)
  function bytesToUInt56(bytes memory _bytes, uint256 _start) internal pure returns (uint56 r) {
    uint256 offset = _start + 0x7;
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

  // NOTE: theoretically possible overflow of (_start + 0x4)
  function bytesToUInt32(bytes memory _bytes, uint256 _start) internal pure returns (uint32 r) {
    uint256 offset = _start + 0x4;
    require(_bytes.length >= offset, "S");
    assembly {
      r := mload(add(_bytes, offset))
    }
  }

  // NOTE: theoretically possible overflow of (_start + 0x3)
  function bytesToUInt24(bytes memory _bytes, uint256 _start) internal pure returns (uint24 r) {
    uint256 offset = _start + 0x3;
    require(_bytes.length >= offset, "S");
    assembly {
      r := mload(add(_bytes, offset))
    }
  }

  // NOTE: theoretically possible overflow of (_start + 0x2)
  function bytesToUInt16(bytes memory _bytes, uint256 _start) internal pure returns (uint16 r) {
    uint256 offset = _start + 0x2;
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

  // NOTE: theoretically possible overflow of (_offset + 7)
  function readUInt56(bytes memory _data, uint256 _offset) internal pure returns (uint256 newOffset, uint56 r) {
    newOffset = _offset + 7;
    r = bytesToUInt56(_data, _offset);
  }

  /// @dev Theoretically possible overflow of (_offset + 0x6)
  function readUInt48(bytes memory _data, uint256 _offset) internal pure returns (uint256 newOffset, uint48 r) {
    newOffset = _offset + 6;
    r = bytesToUInt48(_data, _offset);
  }

  // NOTE: theoretically possible overflow of (_offset + 4)
  function readUInt32(bytes memory _data, uint256 _offset) internal pure returns (uint256 newOffset, uint32 r) {
    newOffset = _offset + 4;
    r = bytesToUInt32(_data, _offset);
  }

  // NOTE: theoretically possible overflow of (_offset + 3)
  function readUInt24(bytes memory _data, uint256 _offset) internal pure returns (uint256 newOffset, uint24 r) {
    newOffset = _offset + 3;
    r = bytesToUInt24(_data, _offset);
  }

  // NOTE: theoretically possible overflow of (_offset + 2)
  function readUInt16(bytes memory _data, uint256 _offset) internal pure returns (uint256 newOffset, uint16 r) {
    newOffset = _offset + 2;
    r = bytesToUInt16(_data, _offset);
  }

  /// @dev Theoretically possible overflow of (_offset + 0x1)
  function readUInt8(bytes memory _data, uint256 _offset) internal pure returns (uint256 newOffset, uint8 r) {
    newOffset = _offset + 1;
    r = uint8(_data[_offset]);
  }
}
