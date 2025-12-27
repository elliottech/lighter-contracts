// Make sure this is set to 1 when running on hardhat network.
// Same value works for other networks too, however better to choose bigger value for testnet
export const TRANSACTION_BLOCK_WAIT = 1;
export const NULL_ADDRESS = '0x0000000000000000000000000000000000000000';
export const NON_NULL_ADDRESS = '0x0000000000000000000000000000000000000001';
export const VALIDATOR_ADDRESS = '0x0000000000000000000000000000000000000004';

export const FILLED_GAS_RESERVE_VALUE = 255; // Equivalent to 0xFF in hexadecimal
