import { utils } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber } from '@ethersproject/bignumber';

export const EMPTY_STRING_KECCAK = '0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470';
export const SCALAR_FIELD = BigNumber.from('0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001');

export const genesisStateRoot = ethers.encodeBytes32String('genesisStateRoot');
export const genesisValidiumRoot = ethers.encodeBytes32String('genesisValidiumRoot');
export const commitment = ethers.encodeBytes32String('commitment');
export const genesisBatch: StoredBatchInfo = {
  batchNumber: 0,
  endBlockNumber: 0,
  batchSize: 0,
  startTimestamp: 0,
  endTimestamp: 0,
  priorityRequestCount: 0,
  prefixPriorityRequestHash: ethers.ZeroHash,
  onChainOperationsHash: ethers.ZeroHash,
  stateRoot: genesisStateRoot,
  validiumRoot: genesisValidiumRoot,
  commitment,
};

export const getKeccak256 = (name: string) => {
  return ethers.keccak256(ethers.toUtf8Bytes(name));
};

export const transferFunds = async (signer: SignerWithAddress, to: string, amount: string) => {
  const tx = await signer.sendTransaction({
    from: await signer.getAddress(),
    to,
    value: ethers.parseEther(amount),
  });
  await tx.wait();
};

export const approveUSDC = async (wallet: SignerWithAddress, usdc: Contract, zklighter: Contract, amount: string) => {
  const a = ethers.parseUnits(amount, 6); // Assuming USDC has 6 decimals
  const setAllowanceTx = await usdc.connect(wallet).approve(await zklighter.getAddress(), a);
  await setAllowanceTx.wait();

  const mint = await usdc.mint(await wallet.getAddress(), a);
  await mint.wait();
};

export const getNewRoots = async (index: number) => {
  return {
    newStateRoot: ethers.encodeBytes32String('newStateRoot' + index),
    newValidiumRoot: ethers.encodeBytes32String('newValidiumRoot' + index),
  };
};

export interface StoredBatchInfo {
  batchNumber: number;
  endBlockNumber: number;
  batchSize: number;
  startTimestamp: number;
  endTimestamp: number;
  priorityRequestCount: number;
  prefixPriorityRequestHash: string;
  onChainOperationsHash: string;
  stateRoot: string;
  validiumRoot: string;
  commitment: string;
}

export interface CommitBatchInfo {
  endBlockNumber: number;
  batchSize: number;
  startTimestamp: number;
  endTimestamp: number;
  priorityRequestCount: number;
  prefixPriorityRequestHash: string;
  onChainOperationsHash: string;
  newStateRoot: string;
  newValidiumRoot: string;
  pubdataCommitments: string;
}

export function hashStoredBatchInfo(batch: StoredBatchInfo) {
  const encode = ethers.AbiCoder.defaultAbiCoder().encode(
    ['uint64', 'uint64', 'uint32', 'uint64', 'uint64', 'uint32', 'bytes32', 'bytes32', 'bytes32', 'bytes32', 'bytes32'],
    [
      batch.batchNumber,
      batch.endBlockNumber,
      batch.batchSize,
      batch.startTimestamp,
      batch.endTimestamp,
      batch.priorityRequestCount,
      batch.prefixPriorityRequestHash,
      batch.onChainOperationsHash,
      batch.stateRoot,
      batch.validiumRoot,
      batch.commitment,
    ],
  );
  return ethers.keccak256(encode);
}

export function calculateCommitment(batch: CommitBatchInfo, blobCommitment: string, oldStateRoot: string) {
  return ethers.solidityPackedKeccak256(
    [
      'uint64',
      'uint32',
      'uint64',
      'uint64',
      'bytes32',
      'bytes32',
      'bytes32',
      'bytes32',
      'uint32',
      'bytes32',
      'bytes32',
    ],
    [
      batch.endBlockNumber,
      batch.batchSize,
      batch.startTimestamp,
      batch.endTimestamp,
      oldStateRoot,
      batch.newStateRoot,
      batch.newValidiumRoot,
      batch.onChainOperationsHash,
      batch.priorityRequestCount,
      batch.prefixPriorityRequestHash,
      blobCommitment,
    ],
  );
}

export enum PriorityPubDataType {
  Empty = 30,
  // L1 transactions
  L1Deposit,
  L1ChangePubKey,
  L1CreateMarket,
  L1UpdateMarket,
  L1CancelAllOrders,
  L1Withdraw,
  L1CreateOrder,
  L1BurnShares,
}

export enum OnChainPubDataType {
  Empty,
  Withdraw,
}

export function encodePubData(pubDataType: string[], pubData: ReadonlyArray<any>) {
  return ethers.solidityPacked(pubDataType, pubData);
}

export function encodePackPubData(pubDataType: string[], pubData: ReadonlyArray<any>, pubDataLength: number) {
  let data = ethers.solidityPacked(pubDataType, pubData);

  while (data.length < pubDataLength * 2 + 2) {
    data += '00';
  }

  return data;
}

export function padEndBytes(data: string, length: number) {
  while (data.length < length * 2 + 2) {
    data += '00';
  }

  return data;
}

export const PubDataTypeMap = {
  [PriorityPubDataType.L1Deposit]: ['uint8', 'uint48', 'address', 'uint64'],
  [PriorityPubDataType.L1CreateMarket]: [
    'uint8',
    'uint8',
    'uint32',
    'uint32',
    'uint32',
    'uint32',
    'uint64',
    'uint64',
    'uint16',
    'uint16',
    'uint16',
    'uint16',
    'uint32',
    'uint8',
    'uint8',
    'uint24',
    'uint24',
    'uint56',
    'uint48',
    'bytes32',
  ],
  [PriorityPubDataType.L1UpdateMarket]: [
    'uint8',
    'uint8',
    'uint32',
    'uint32',
    'uint32',
    'uint32',
    'uint64',
    'uint64',
    'uint16',
    'uint16',
    'uint16',
    'uint16',
    'uint32',
    'uint24',
    'uint24',
    'uint56',
    'uint48',
  ],
  [PriorityPubDataType.L1ChangePubKey]: ['uint8', 'uint48', 'uint48', 'uint8', 'bytes'],
  [PriorityPubDataType.L1Withdraw]: ['uint8', 'uint48', 'uint48', 'uint64'],
  [PriorityPubDataType.L1CancelAllOrders]: ['uint8', 'uint48', 'uint48'],
  [PriorityPubDataType.L1CreateOrder]: ['uint8', 'uint48', 'uint48', 'uint8', 'uint48', 'uint32', 'uint8', 'uint8'],
  [PriorityPubDataType.L1BurnShares]: ['uint8', 'uint48', 'uint48', 'uint48', 'uint64'],
};

export interface CreateMarket {
  marketIndex: number;
  quoteMultiplier: number;
  takerFee: number;
  makerFee: number;
  liquidationFee: number;
  minBaseAmount: number;
  minQuoteAmount: number;
  defaultInitialMarginFraction: number;
  minInitialMarginFraction: number;
  maintenanceMarginFraction: number;
  closeOutMarginFraction: number;
  interestRate: number;
  fundingClampSmall: number;
  fundingClampBig: number;
  openInterestLimit: number;
  orderQuoteLimit: number;
}

export function emptyCreateMarket(marketIndex: number): CreateMarket {
  return {
    marketIndex,
    quoteMultiplier: 0,
    takerFee: 0,
    makerFee: 0,
    liquidationFee: 0,
    minBaseAmount: 0,
    minQuoteAmount: 0,
    defaultInitialMarginFraction: 0,
    minInitialMarginFraction: 0,
    maintenanceMarginFraction: 0,
    closeOutMarginFraction: 0,
    interestRate: 0,
    fundingClampSmall: 0,
    fundingClampBig: 0,
    openInterestLimit: 0,
    orderQuoteLimit: 0,
  };
}

export interface UpdateMarket {
  marketIndex: number;
  status: number;
  takerFee: number;
  makerFee: number;
  liquidationFee: number;
  minBaseAmount: number;
  minQuoteAmount: number;
  defaultInitialMarginFraction: number;
  minInitialMarginFraction: number;
  maintenanceMarginFraction: number;
  closeOutMarginFraction: number;
  interestRate: number;
  fundingClampSmall: number;
  fundingClampBig: number;
  openInterestLimit: number;
  orderQuoteLimit: number;
}

export function emptyUpdateMarket(marketIndex: number, status: number): UpdateMarket {
  return {
    marketIndex,
    status,
    takerFee: 0,
    makerFee: 0,
    liquidationFee: 0,
    minBaseAmount: 0,
    minQuoteAmount: 0,
    defaultInitialMarginFraction: 0,
    minInitialMarginFraction: 0,
    maintenanceMarginFraction: 0,
    closeOutMarginFraction: 0,
    interestRate: 0,
    fundingClampSmall: 0,
    fundingClampBig: 0,
    openInterestLimit: 0,
    orderQuoteLimit: 0,
  };
}

export function numberToBytesBE(number: number, bytes: number): Uint8Array {
  const result = new Uint8Array(bytes);
  for (let i = bytes - 1; i >= 0; i--) {
    result[i] = number & 0xff;
    number >>= 8;
  }
  return result;
}

export function serializeNonce(nonce: number): Uint8Array {
  return numberToBytesBE(nonce, 4);
}

export function serializeAccountIndex(accountIndex: number): Uint8Array {
  return numberToBytesBE(accountIndex, 4);
}

export function getChangePubkeyMessage(
  pubKeyX: string,
  pubKeyY: string,
  nonce: number,
  accountIndex: number,
): Uint8Array {
  const msgNonce = utils.hexlify(serializeNonce(nonce));
  const msgAccountIndex = utils.hexlify(serializeAccountIndex(accountIndex));
  const message =
    `Register zkLighter Account\n\n` +
    `pubkeyX: ` +
    `${pubKeyX}\n` +
    `pubkeyY: ` +
    `${pubKeyY}\n` +
    `nonce: ${msgNonce}\n` +
    `account index: ${msgAccountIndex}\n\n` +
    `Only sign this message for a trusted client!`;
  return utils.toUtf8Bytes(message);
}

export const advanceBlocks = async (blocksToIncrement: number): Promise<number> => {
  for (let i = 0; i < blocksToIncrement; i++) {
    // Mine additional blocks to increment the block number
    await ethers.provider.send('evm_mine', []);
  }

  // Get the current block number after mining
  return await ethers.provider.getBlockNumber();
};

export const incrementBlockstampBySeconds = async (seconds: number) => {
  const currentBlocktimestamp = await getBlockTimestamp();
  await setNextBlockTimestamp((currentBlocktimestamp as number) + seconds);
  return getBlockTimestamp();
};

export const setNextBlockTimestamp = async (timestampInSeconds: number) => {
  await ethers.provider.send('evm_setNextBlockTimestamp', [timestampInSeconds]);
};

export const getBlockNumber = async (): Promise<number> => {
  // Get the current block number
  return await ethers.provider.getBlockNumber();
};

export const getBlockTimestamp = async (): Promise<number> => {
  // Get the current block number
  const blockNumber = await ethers.provider.getBlockNumber();

  // Get the block information for the current block
  const block = await ethers.provider.getBlock(blockNumber);

  // Retrieve the timestamp of the current block
  return block.timestamp;
};
