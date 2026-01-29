// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

/// @title zkLighter Configuration Contract
/// @author zkLighter Team
contract Config {
  /// @dev Max master account id that could be registered in the
  /// network (excluding treasury, which is set as accountIndex = 0)
  /// Sub accounts and pool indexes start from 2**47 to 2**48 - 2 and are set by the sequencer
  uint48 public constant MAX_MASTER_ACCOUNT_INDEX = 2 ** 47 - 1;

  /// @dev Max account id that could be registered in the network
  uint48 public constant MAX_ACCOUNT_INDEX = 2 ** 48 - 2;

  /// @dev Nil account id, that represents an empty account
  uint48 public constant NIL_ACCOUNT_INDEX = 2 ** 48 - 1;

  /// @dev Max API key index that could be registered for an account
  uint8 public constant MAX_API_KEY_INDEX = 254; // 2 ** 8 - 2

  /// @dev Min asset index that could be registered in the exchange
  uint16 public constant MIN_ASSET_INDEX = 1;

  /// @dev Native asset index, that represents the base chain native asset (ETH)
  uint16 public constant NATIVE_ASSET_INDEX = 1;

  /// @dev USDC asset index
  uint16 public constant USDC_ASSET_INDEX = 3;

  /// @dev Max asset index that could be registered in the exchange (to be extended in the future)
  uint16 public constant MAX_ASSET_INDEX = 62; // 2 ** 6 - 2

  /// @dev Max tick size for an asset
  uint128 public constant MAX_TICK_SIZE = 2 ** 128 - 1;

  /// @dev Max deposit cap ticks for an asset
  uint64 public constant MAX_DEPOSIT_CAP_TICKS = 2 ** 60 - 1;

  /// @dev Max perps market index that could be registered to the exchange
  uint16 public constant MAX_PERPS_MARKET_INDEX = 254; // 2 ** 8 - 2

  /// @dev Min spot market index that could be registered to the exchange
  uint16 public constant MIN_SPOT_MARKET_INDEX = 2048; // 2 ** 11

  /// @dev Max spot market index that could be registered to the exchange
  uint16 public constant MAX_SPOT_MARKET_INDEX = 4094; // 2 ** 12 - 2

  /// @dev Max price an order can have
  uint32 public constant MAX_ORDER_PRICE = 2 ** 32 - 1;

  /// @dev Min price an order can have
  uint32 public constant MIN_ORDER_PRICE = 1;

  /// @dev Nil order base amount
  uint48 public constant NIL_ORDER_BASE_AMOUNT = 0;

  /// @dev Max order base amount
  uint48 public constant MAX_ORDER_BASE_AMOUNT = 2 ** 48 - 1;

  /// @dev Max order quote amount
  uint48 public constant MAX_ORDER_QUOTE_AMOUNT = 2 ** 48 - 1;

  /// @dev Min order base amount
  uint48 public constant MIN_ORDER_BASE_AMOUNT = 1;

  /// @dev Max amount of pool shares that can be minted or burned
  uint64 public constant MAX_POOL_SHARES_TO_MINT_OR_BURN = 2 ** 60 - 1;

  /// @dev Min amount of pool shares that can be minted or burned
  uint64 public constant MIN_POOL_SHARES_TO_MINT_OR_BURN = 1;

  /// @dev Max amount of staking shares that can be minted or burned
  uint64 public constant MAX_STAKING_SHARES_TO_MINT_OR_BURN = 2 ** 60 - 1;

  /// @dev Min amount of staking shares that can be minted or burned
  uint64 public constant MIN_STAKING_SHARES_TO_MINT_OR_BURN = 1;

  /// @dev Expiration timestamp delta for priority request
  /// @dev Priority expiration timestamp should be greater than the operation execution timestamp
  uint256 public constant PRIORITY_EXPIRATION = 14 days;

  /// @dev Margin tick to transform margin values in form x * 0.01%
  uint16 constant MARGIN_TICK = 10_000;

  /// @dev Funding rate tick to transform funding values in form x * 0.0001%
  uint32 constant FUNDING_RATE_TICK = 1_000_000;

  /// @dev Fee tick to transform fee values in form x * 0.0001%
  uint32 constant FEE_TICK = 1_000_000;

  /// @dev Max value for quote multiplier
  uint32 constant MAX_QUOTE_MULTIPLIER = 10_000;

  /// @dev Max value for asset extension multiplier
  uint56 constant MAX_ASSET_EXTENSION_MULTIPLIER = 2 ** 56 - 1;

  /// @dev Max value for asset extended deposit cap ticks
  uint128 constant MAX_EXTENDED_DEPOSIT_CAP_TICKS = 2 ** 80 - 1;

  /// @dev Size of the public key for a Lighter API key
  uint8 constant PUB_KEY_BYTES_SIZE = 40;

  /// @dev Address of the blob point evaluation precompile (EIP-4844)
  address constant POINT_EVALUATION_PRECOMPILE_ADDRESS = address(0x0A);

  /// @dev Max priority request pubdata size stat is written to the priority request queue
  uint256 constant MAX_PRIORITY_REQUEST_PUBDATA_SIZE = 100;

  /// @dev BLS Modulus value defined in EIP-4844,
  /// returned by the precompile if successfully evaluated
  uint256 constant BLS_MODULUS = 52435875175126190479447740508185965837690552500527637822603658699938581184513;

  /// @dev Scalar field of bn254
  uint256 constant BN254_MODULUS = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

  /// @dev Evaluation point x (32 bytes) || evaluation point y (32 bytes) ||
  /// commitment (48 bytes) || proof (48 bytes)) = 160 bytes
  uint256 constant BLOB_DATA_COMMITMENT_BYTE_SIZE = 160;

  /// @dev Goldilocks prime field modulus, 2^64 - 2^32 + 1
  uint64 constant GOLDILOCKS_MODULUS = 0xffffffff00000001;

  /// @dev Max open interest per market
  uint64 constant MAX_MARKET_OPEN_INTEREST = (2 ** 56) - 1;

  /// @dev Max batch deposit length
  uint64 public constant MAX_BATCH_DEPOSIT_LENGTH = 1000;

  /// @dev Max # of blobs a batch can have
  uint256 constant MAX_BLOB_COUNT = 6;

  /// @dev Treasury account index (system account)
  uint48 constant TREASURY_ACCOUNT_INDEX = 0;

  /// @dev Insurance fund operator account index (system account)
  uint48 constant INSURANCE_FUND_OPERATOR_ACCOUNT_INDEX = 1; // Account index for the insurance fund operator account

  /// @dev Max system account index, 2 is left empty for future use
  uint48 constant MAX_SYSTEM_ACCOUNT_INDEX = 2;

  function _hasCode(address account) internal view returns (bool) {
    return account.code.length > 0;
  }

  uint48 constant MAX_CONFIG_PERIOD = 1000 * 60 * 60 * 24 * 14; // 14 days in milliseconds
}
