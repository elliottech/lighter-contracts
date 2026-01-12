import { Contract } from 'ethers';
import { expect } from 'chai';
import {
  CreateMarket,
  PriorityPubDataType,
  PubDataTypeMap,
  UpdateMarket,
  advanceBlocks,
  emptyCreatePerpsMarket,
  emptyCreateSpotMarket,
  emptyUpdatePerpsMarket,
  emptyUpdateSpotMarket,
  encodePubData,
  getExpirationTimestamp,
  getNextPriorityRequestId,
  getZKLighterTestSetupValues,
  incrementBlockstampBySeconds,
  serializeCreatePerpsMarket,
  serializeCreateSpotMarket,
  serializeUpdatePerpsMarket,
  serializeUpdateSpotMarket,
} from './shared';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber } from '@ethersproject/bignumber';
import { randomBytes } from 'crypto';

const GOLDILOCKS_MODULUS = 0xffffffff00000001n;

function toLittleEndianBytes(num: bigint): Uint8Array {
  const arr = new Uint8Array(8);
  let n = num;
  for (let i = 0; i < 8; i++) {
    arr[i] = Number(n & 0xffn);
    n >>= 8n;
  }
  return arr;
}

function randomBigInt(max: bigint): bigint {
  const byteLength = Math.ceil(Number(max.toString(2).length) / 8);
  let rand: bigint;
  do {
    const buf = randomBytes(byteLength);
    rand = BigInt('0x' + buf.toString('hex'));
  } while (rand >= max);
  return rand;
}

function randomValidPubKey(): Buffer {
  const arr = [
    randomBigInt(GOLDILOCKS_MODULUS),
    randomBigInt(GOLDILOCKS_MODULUS),
    randomBigInt(GOLDILOCKS_MODULUS),
    randomBigInt(GOLDILOCKS_MODULUS),
    randomBigInt(GOLDILOCKS_MODULUS),
  ].map(toLittleEndianBytes);
  const flat = arr.reduce((acc, val) => acc.concat(Array.from(val)), [] as number[]);
  return Buffer.from(flat);
}

export async function getPendingBalanceData(zkLighter: Contract, account: string, assetId: number) {
  const pendingBalanceData = await zkLighter.getPendingBalances(account, assetId);
  return {
    balanceToWithdraw: BigNumber.from(pendingBalanceData[0].toString()),
    reserveValue: BigNumber.from(pendingBalanceData[1].toString()),
  };
}

export async function getAccountIndex(zkLighter: Contract, receiver: SignerWithAddress) {
  const index = await zkLighter.addressToAccountIndex(await receiver.getAddress());
  if (index == 0) {
    return (await zkLighter.lastAccountIndex()) + 1n;
  }
  return index;
}

export async function withdrawUSDC(zkLighter: Contract, amount: number, token: Contract, sender: SignerWithAddress) {
  const index = await getAccountIndex(zkLighter, sender);
  const nextPriorityRequestId: number = await getNextPriorityRequestId(zkLighter);
  const tx = await zkLighter.connect(sender).withdraw(index, 3, 0, amount);
  await tx.wait();
  const expirationTimestamp: number = await getExpirationTimestamp(zkLighter);

  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1Withdraw], [
    PriorityPubDataType.L1Withdraw,
    index,
    index,
    3,
    0,
    amount,
  ]);

  await expect(tx)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(sender.address, nextPriorityRequestId, PriorityPubDataType.L1Withdraw, pubData, expirationTimestamp)
    .to.emit(zkLighter, 'Withdraw')
    .withArgs(index, 3, 0, amount);
  return { tx, pubData };
}

export async function withdrawNative(zkLighter: Contract, amount: number, sender: SignerWithAddress) {
  const index = await getAccountIndex(zkLighter, sender);
  const nextPriorityRequestId: number = await getNextPriorityRequestId(zkLighter);
  const tx = await zkLighter.connect(sender).withdraw(index, 1, 0, amount);
  await tx.wait();
  const expirationTimestamp: number = await getExpirationTimestamp(zkLighter);

  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1Withdraw], [
    PriorityPubDataType.L1Withdraw,
    index,
    index,
    1,
    0,
    amount,
  ]);

  await expect(tx)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(sender.address, nextPriorityRequestId, PriorityPubDataType.L1Withdraw, pubData, expirationTimestamp)
    .to.emit(zkLighter, 'Withdraw')
    .withArgs(index, 1, 0, amount);
  return { tx, pubData };
}

export async function cancelAllOrders(zkLighter: Contract, sender: SignerWithAddress) {
  const index = await getAccountIndex(zkLighter, sender);
  const nextPriorityRequestId: number = await getNextPriorityRequestId(zkLighter);
  const tx = await zkLighter.connect(sender).cancelAllOrders(index);
  await tx.wait();
  const expirationTimestamp: number = await getExpirationTimestamp(zkLighter);

  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1CancelAllOrders], [
    PriorityPubDataType.L1CancelAllOrders,
    index,
    index,
  ]);

  await expect(tx)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(
      sender.address,
      nextPriorityRequestId,
      PriorityPubDataType.L1CancelAllOrders,
      pubData,
      expirationTimestamp,
    )
    .to.emit(zkLighter, 'CancelAllOrders')
    .withArgs(index);
  return { tx, pubData };
}

export async function changePubKey(
  zkLighter: Contract,
  sender: SignerWithAddress,
  apiKeyIndex: number,
  pubKey: Buffer,
) {
  const index = await getAccountIndex(zkLighter, sender);
  const nextPriorityRequestId = await getNextPriorityRequestId(zkLighter);
  const tx = await zkLighter.connect(sender).changePubKey(index, apiKeyIndex, pubKey);
  await tx.wait();
  const expirationTimestamp = await getExpirationTimestamp(zkLighter);

  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1ChangePubKey], [
    PriorityPubDataType.L1ChangePubKey,
    index,
    index,
    apiKeyIndex,
    pubKey,
  ]);

  await expect(tx)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(sender.address, nextPriorityRequestId, PriorityPubDataType.L1ChangePubKey, pubData, expirationTimestamp)
    .to.emit(zkLighter, 'ChangePubKey')
    .withArgs(index, apiKeyIndex, pubKey);
  return { tx, pubData };
}

export async function createOrder(
  zkLighter: Contract,
  sender: SignerWithAddress,
  marketIndex: number,
  baseAmount: number,
  price: number,
  isAsk: number,
  orderType: number,
) {
  const index = await getAccountIndex(zkLighter, sender);
  const nextPriorityRequestId: number = await getNextPriorityRequestId(zkLighter);
  const tx = await zkLighter.connect(sender).createOrder(index, marketIndex, baseAmount, price, isAsk, orderType);
  await tx.wait();
  const expirationTimestamp: number = await getExpirationTimestamp(zkLighter);

  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1CreateOrder], [
    PriorityPubDataType.L1CreateOrder,
    index,
    index,
    marketIndex,
    baseAmount,
    price,
    isAsk,
    orderType,
  ]);

  await expect(tx)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(sender.address, nextPriorityRequestId, PriorityPubDataType.L1CreateOrder, pubData, expirationTimestamp)
    .to.emit(zkLighter, 'CreateOrder')
    .withArgs([index, index, marketIndex, baseAmount, price, isAsk, orderType]);
  return { tx, pubData };
}

export async function burnShares(
  zkLighter: Contract,
  sender: SignerWithAddress,
  poolIndex: number,
  shareAmount: number,
) {
  const index = await getAccountIndex(zkLighter, sender);
  const nextPriorityRequestId: number = await getNextPriorityRequestId(zkLighter);
  const tx = await zkLighter.connect(sender).burnShares(index, poolIndex, shareAmount);
  await tx.wait();
  const expirationTimestamp: number = await getExpirationTimestamp(zkLighter);

  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1BurnShares], [
    PriorityPubDataType.L1BurnShares,
    index,
    index,
    poolIndex,
    shareAmount,
  ]);

  await expect(tx)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(sender.address, nextPriorityRequestId, PriorityPubDataType.L1BurnShares, pubData, expirationTimestamp)
    .to.emit(zkLighter, 'BurnShares')
    .withArgs([index, index, poolIndex, shareAmount]);
  return { tx, pubData };
}

export async function depositUSDC(
  zkLighter: Contract,
  transferAmount: number,
  token: Contract,
  sender: SignerWithAddress,
  receiver: SignerWithAddress,
) {
  const index = await getAccountIndex(zkLighter, receiver);
  const nextPriorityRequestId: number = await getNextPriorityRequestId(zkLighter);
  const tx = await zkLighter.connect(sender).deposit(await receiver.getAddress(), 3, 0, transferAmount);
  await tx.wait();
  const expirationTimestamp: number = await getExpirationTimestamp(zkLighter);

  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1Deposit], [
    PriorityPubDataType.L1Deposit,
    index,
    await receiver.getAddress(),
    3,
    0,
    transferAmount,
  ]);

  await expect(tx)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(sender.address, nextPriorityRequestId, PriorityPubDataType.L1Deposit, pubData, expirationTimestamp)
    .to.emit(zkLighter, 'Deposit')
    .withArgs(index, await receiver.getAddress(), 3, 0, transferAmount);

  const indexAfter = await zkLighter.addressToAccountIndex(await receiver.getAddress());
  expect(indexAfter).to.eq(index);

  return { tx, pubData };
}

export async function depositUSDCToSystemAccount(
  zkLighter: Contract,
  transferAmount: number,
  token: Contract,
  sender: SignerWithAddress,
  receiver: SignerWithAddress,
  receiverIndex: number,
) {
  const nextPriorityRequestId: number = await getNextPriorityRequestId(zkLighter);
  const tx = await zkLighter.connect(sender).deposit(await receiver.getAddress(), 3, 0, transferAmount);
  await tx.wait();
  const expirationTimestamp: number = await getExpirationTimestamp(zkLighter);

  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1Deposit], [
    PriorityPubDataType.L1Deposit,
    receiverIndex,
    ethers.ZeroAddress,
    3,
    0,
    transferAmount,
  ]);

  await expect(tx)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(sender.address, nextPriorityRequestId, PriorityPubDataType.L1Deposit, pubData, expirationTimestamp)
    .to.emit(zkLighter, 'Deposit')
    .withArgs(receiverIndex, ethers.ZeroAddress, 3, 0, transferAmount);

  const indexAfter = await zkLighter.addressToAccountIndex(await receiver.getAddress());
  expect(indexAfter).to.eq(0);

  return { tx, pubData };
}

export async function createSpotMarket(
  zkLighter: Contract,
  governorWallet: SignerWithAddress,
  sizeDecimals: number,
  priceDecimals: number,
  symbol: string,
  params: any,
) {
  const marketData = ethers.solidityPacked(
    ['uint16', 'uint16', 'uint56', 'uint56', 'uint32', 'uint32', 'uint48', 'uint48', 'uint48'],
    [
      params.baseAssetIndex,
      params.quoteAssetIndex,
      params.sizeExtensionMultiplier,
      params.quoteExtensionMultiplier,
      params.takerFee,
      params.makerFee,
      params.minBaseAmount,
      params.minQuoteAmount,
      params.orderQuoteLimit,
    ],
  );
  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1CreateMarket], [
    PriorityPubDataType.L1CreateMarket,
    params.marketIndex,
    1, // marketType
    marketData,
    sizeDecimals,
    priceDecimals,
    symbol,
  ]);

  const nextPriorityRequestId: number = await getNextPriorityRequestId(zkLighter);

  const createMarketParams = {
    marketIndex: params.marketIndex,
    marketType: 1,
    marketData,
  } as CreateMarket;

  const tx = await zkLighter
    .connect(governorWallet)
    .createMarket(sizeDecimals, priceDecimals, symbol, createMarketParams);
  const receipt = await tx.wait();
  const expirationTimestamp: number = await getExpirationTimestamp(zkLighter);

  expect(tx)
    .to.emit(zkLighter, 'CreateMarket')
    .withArgs(createMarketParams, sizeDecimals, priceDecimals, symbol)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(
      governorWallet.address,
      nextPriorityRequestId,
      PriorityPubDataType.L1CreateMarket,
      pubData,
      expirationTimestamp,
    );

  return { tx, pubData, receipt };
}

export async function createPerpsMarket(
  zkLighter: Contract,
  governorWallet: SignerWithAddress,
  sizeDecimals: number,
  priceDecimals: number,
  symbol: string,
  params: any,
) {
  const marketData = ethers.solidityPacked(
    [
      'uint32',
      'uint32',
      'uint32',
      'uint32',
      'uint48',
      'uint48',
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
    [
      params.quoteMultiplier,
      params.takerFee,
      params.makerFee,
      params.liquidationFee,
      params.minBaseAmount,
      params.minQuoteAmount,
      params.defaultInitialMarginFraction,
      params.minInitialMarginFraction,
      params.maintenanceMarginFraction,
      params.closeOutMarginFraction,
      params.interestRate,
      params.fundingClampSmall,
      params.fundingClampBig,
      params.openInterestLimit,
      params.orderQuoteLimit,
    ],
  );
  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1CreateMarket], [
    PriorityPubDataType.L1CreateMarket,
    params.marketIndex,
    0, // marketType
    marketData,
    sizeDecimals,
    priceDecimals,
    symbol,
  ]);

  const nextPriorityRequestId: number = await getNextPriorityRequestId(zkLighter);

  const createMarketParams = {
    marketIndex: params.marketIndex,
    marketType: 0,
    marketData,
  } as CreateMarket;

  const tx = await zkLighter
    .connect(governorWallet)
    .createMarket(sizeDecimals, priceDecimals, symbol, createMarketParams);
  const receipt = await tx.wait();
  const expirationTimestamp: number = await getExpirationTimestamp(zkLighter);

  expect(tx)
    .to.emit(zkLighter, 'CreateMarket')
    .withArgs(createMarketParams, sizeDecimals, priceDecimals, symbol)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(
      governorWallet.address,
      nextPriorityRequestId,
      PriorityPubDataType.L1CreateMarket,
      pubData,
      expirationTimestamp,
    );

  return { tx, pubData, receipt };
}

export async function updatePerpsMarket(zkLighter: Contract, governorWallet: SignerWithAddress, params: any) {
  const marketData = ethers.solidityPacked(
    [
      'uint8',
      'uint32',
      'uint32',
      'uint32',
      'uint48',
      'uint48',
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
    [
      params.status,
      params.takerFee,
      params.makerFee,
      params.liquidationFee,
      params.minBaseAmount,
      params.minQuoteAmount,
      params.defaultInitialMarginFraction,
      params.minInitialMarginFraction,
      params.maintenanceMarginFraction,
      params.closeOutMarginFraction,
      params.interestRate,
      params.fundingClampSmall,
      params.fundingClampBig,
      params.openInterestLimit,
      params.orderQuoteLimit,
    ],
  );

  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1UpdateMarket], [
    PriorityPubDataType.L1UpdateMarket,
    params.marketIndex,
    0, // marketType
    marketData,
  ]);

  const nextPriorityRequestId: number = await getNextPriorityRequestId(zkLighter);

  const updateMarketParams = {
    marketIndex: params.marketIndex,
    marketType: 0,
    marketData,
  } as UpdateMarket;
  const tx = await zkLighter.connect(governorWallet).updateMarket(updateMarketParams);
  const receipt = await tx.wait();
  const expirationTimestamp: number = await getExpirationTimestamp(zkLighter);

  expect(tx)
    .to.emit(zkLighter, 'UpdateMarket')
    .withArgs(params)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(
      governorWallet.address,
      nextPriorityRequestId,
      PriorityPubDataType.L1UpdateMarket,
      pubData,
      expirationTimestamp,
    );

  return { tx, pubData, receipt };
}

export async function updateSpotMarket(zkLighter: Contract, governorWallet: SignerWithAddress, params: any) {
  const marketData = ethers.solidityPacked(
    ['uint8', 'uint32', 'uint32', 'uint48', 'uint48', 'uint48'],
    [
      params.status,
      params.takerFee,
      params.makerFee,
      params.minBaseAmount,
      params.minQuoteAmount,
      params.orderQuoteLimit,
    ],
  );

  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1UpdateMarket], [
    PriorityPubDataType.L1UpdateMarket,
    params.marketIndex,
    1, // marketType
    marketData,
  ]);

  const nextPriorityRequestId: number = await getNextPriorityRequestId(zkLighter);

  const updateMarketParams = {
    marketIndex: params.marketIndex,
    marketType: 1,
    marketData,
  } as UpdateMarket;
  const tx = await zkLighter.connect(governorWallet).updateMarket(updateMarketParams);
  const receipt = await tx.wait();
  const expirationTimestamp: number = await getExpirationTimestamp(zkLighter);

  expect(tx)
    .to.emit(zkLighter, 'UpdateMarket')
    .withArgs(params)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(
      governorWallet.address,
      nextPriorityRequestId,
      PriorityPubDataType.L1UpdateMarket,
      pubData,
      expirationTimestamp,
    );

  return { tx, pubData, receipt };
}

export async function activateDesertMode(
  zkLighter: Contract,
  sender: SignerWithAddress,
  receiver: SignerWithAddress,
): Promise<boolean> {
  // make few deposit requests
  let lighterTx = await depositETH(zkLighter, BigNumber.from(10), sender, receiver);
  lighterTx = await depositETH(zkLighter, BigNumber.from(10), sender, receiver);

  //default expiration period is 201600 we need to decrease it to fasten test enviroment
  await zkLighter.setExpirationBlockNumber(3);

  //advance the blocks so that current-blocknumber will go past the expirationBlockNumber of priorityRequests
  await advanceBlocks(10);

  //call activateDesertMode
  await zkLighter.activateDesertMode();

  const desertModeActivated = await zkLighter.desertMode();

  return desertModeActivated;
}

export async function depositNative(
  zkLighter: Contract,
  transferAmount: number, // in ticks
  sender: SignerWithAddress,
  receiver: SignerWithAddress,
) {
  const index = await getAccountIndex(zkLighter, receiver);
  const nextPriorityRequestId: number = await getNextPriorityRequestId(zkLighter);
  const tx = await zkLighter
    .connect(sender)
    .deposit(
      await receiver.getAddress(),
      1,
      1,
      BigNumber.from(transferAmount).mul(BigNumber.from(10).pow(10)).toString(),
      {
        value: BigNumber.from(transferAmount).mul(BigNumber.from(10).pow(10)).toString(),
      },
    );
  await tx.wait();
  const expirationTimestamp: number = await getExpirationTimestamp(zkLighter);

  const pubData = encodePubData(PubDataTypeMap[PriorityPubDataType.L1Deposit], [
    PriorityPubDataType.L1Deposit,
    index,
    await receiver.getAddress(),
    1,
    1,
    transferAmount,
  ]);

  await expect(tx)
    .to.emit(zkLighter, 'NewPriorityRequest')
    .withArgs(sender.address, nextPriorityRequestId, PriorityPubDataType.L1Deposit, pubData, expirationTimestamp)
    .to.emit(zkLighter, 'Deposit')
    .withArgs(index, await receiver.getAddress(), 1, 1, transferAmount);

  const indexAfter = await zkLighter.addressToAccountIndex(await receiver.getAddress());
  expect(indexAfter).to.eq(index);

  return { tx, pubData };
}

describe('ZkLighter Tests', function () {
  let additionalZkLighter: Contract,
    zkLighterImpl: Contract,
    zkLighter: Contract,
    governance: Contract,
    mockZkLighterVerifier: Contract,
    mockDesertVerifier: Contract;
  let owner: SignerWithAddress,
    sender1: SignerWithAddress,
    sender2: SignerWithAddress,
    receiver1: SignerWithAddress,
    receiver2: SignerWithAddress,
    governorWallet: SignerWithAddress,
    _verifierWallet: SignerWithAddress;
  let usdc: Contract;

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.
  beforeEach(async function () {
    const s = await getZKLighterTestSetupValues();
    ({
      owner,
      _verifierWallet,
      zkLighter,
      zkLighterImpl,
      usdc,
      additionalZkLighter,
      mockZkLighterVerifier,
      mockDesertVerifier,
      governance,
      sender1,
      sender2,
      governorWallet,
      receiver1,
      receiver2,
    } = s);
  });

  describe('Deposit', function () {
    describe('deposit USDC', async function () {
      it('should reverted', async () => {
        // amount check
        await expect(zkLighter.deposit(await receiver1.getAddress(), 3, 0, 0)).to.be.revertedWithCustomError(
          additionalZkLighter,
          'AdditionalZkLighter_InvalidDepositAmount',
        );

        // toAddress should not be zero address
        await expect(zkLighter.deposit(ethers.ZeroAddress, 3, 0, 1_000_000_000)).to.be.revertedWithCustomError(
          additionalZkLighter,
          'AdditionalZkLighter_RecipientAddressInvalid',
        );

        // max deposit amount
        await expect(
          zkLighter.connect(owner).deposit(await receiver1.getAddress(), 3, 0, BigNumber.from(2).pow(60).toString()),
        ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidDepositAmount');
      });

      it('should success', async () => {
        await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);
      });

      it('should register', async () => {
        const indexBefore = await zkLighter.addressToAccountIndex(await receiver1.getAddress());
        expect(indexBefore).to.eq(0);
        await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);
        const indexAfter = await zkLighter.addressToAccountIndex(await receiver1.getAddress());
        expect(indexAfter).to.not.eq(0);
        await depositUSDC(zkLighter, 10_000_000, usdc, sender2, receiver1);
      });

      it('to treasury should success', async () => {
        await zkLighter.connect(governorWallet).setTreasury(receiver1.address);
        await depositUSDCToSystemAccount(zkLighter, 10_000_000, usdc, sender1, receiver1, 0);
      });

      it('to insurance fund should success', async () => {
        await zkLighter.connect(governorWallet).setInsuranceFundOperator(receiver1.address);
        await depositUSDCToSystemAccount(zkLighter, 10_000_000, usdc, sender1, receiver1, 1);
      });
    });

    describe('deposit ETH', async function () {
      it('should success', async () => {
        await depositNative(zkLighter, 1_000_000, sender1, receiver1);
      });

      it('should register', async () => {
        const indexBefore = await zkLighter.addressToAccountIndex(await receiver1.getAddress());
        expect(indexBefore).to.eq(0);
        await depositNative(zkLighter, 1_000_000, sender1, receiver1);
        const indexAfter = await zkLighter.addressToAccountIndex(await receiver1.getAddress());
        expect(indexAfter).to.not.eq(0);
        await depositNative(zkLighter, 1_000_000, sender2, receiver1);
      });
    });
  });

  describe('Withdraw', function () {
    describe('withdraw USDC', async function () {
      it('should reverted', async () => {
        await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);
        const index = await getAccountIndex(zkLighter, receiver1);

        await expect(zkLighter.connect(receiver1).withdraw(index, 3, 0, 0)).to.be.revertedWithCustomError(
          additionalZkLighter,
          'AdditionalZkLighter_InvalidWithdrawAmount',
        );

        await expect(
          zkLighter.connect(receiver1).withdraw(index, 3, 0, BigNumber.from(2).pow(60).toString()),
        ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidWithdrawAmount');

        await expect(zkLighter.connect(receiver1).withdraw(index, 3, 2, 10n)).to.be.revertedWithoutReason();

        await expect(zkLighter.withdraw(index + 5n, 3, 0, 10n)).to.be.revertedWithCustomError(
          additionalZkLighter,
          'AdditionalZkLighter_AccountIsNotRegistered',
        );
      });

      it('should success', async () => {
        await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);
        await withdrawUSDC(zkLighter, 100, usdc, receiver1);
      });
    });

    describe('withdraw ETH', async function () {
      it('should reverted', async () => {
        await depositNative(zkLighter, 10_000_000, sender1, receiver1);
        const index = await getAccountIndex(zkLighter, receiver1);

        await expect(zkLighter.connect(receiver1).withdraw(index, 1, 0, 0)).to.be.revertedWithCustomError(
          additionalZkLighter,
          'AdditionalZkLighter_InvalidWithdrawAmount',
        );

        await expect(
          zkLighter.connect(receiver1).withdraw(index, 1, 0, BigNumber.from(2).pow(60).toString()),
        ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidWithdrawAmount');

        await expect(zkLighter.connect(receiver1).withdraw(index, 1, 2, 10n)).to.be.revertedWithoutReason();

        await expect(zkLighter.withdraw(index + 5n, 1, 0, 10)).to.be.revertedWithCustomError(
          additionalZkLighter,
          'AdditionalZkLighter_AccountIsNotRegistered',
        );
      });

      it('should success', async () => {
        await depositNative(zkLighter, 10_000_000, sender1, receiver1);
        await withdrawNative(zkLighter, 100, receiver1);
      });
    });

    it('should reverted if asset not registered', async () => {
      await depositNative(zkLighter, 10_000_000, sender1, receiver1);
      const index = await getAccountIndex(zkLighter, receiver1);

      await expect(zkLighter.connect(receiver1).withdraw(index, 59, 0, 0)).to.be.revertedWithCustomError(
        additionalZkLighter,
        'AdditionalZkLighter_InvalidAssetIndex',
      );
    });
  });

  describe('ChangePubKey', function () {
    it('should reverted', async () => {
      await expect(
        zkLighter.connect(sender1).changePubKey((1n << 48n) - 1n, 0, randomBytes(40)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidAccountIndex');
      await expect(
        zkLighter.connect(sender1).changePubKey((1n << 48n) - 2n, 255, randomBytes(40)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidApiKeyIndex');
      await expect(
        zkLighter.connect(sender1).changePubKey((1n << 48n) - 2n, 0, randomBytes(41)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidPubKey');
      await expect(
        zkLighter.connect(sender1).changePubKey((1n << 48n) - 2n, 0, Buffer.alloc(40, 0)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidPubKey');

      await expect(
        zkLighter
          .connect(sender1)
          .changePubKey(
            (1n << 48n) - 2n,
            0,
            Buffer.from([1n, 2n, 3n, 4n, GOLDILOCKS_MODULUS].flatMap(toLittleEndianBytes)),
          ),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidPubKey');

      await expect(
        zkLighter.connect(sender1).changePubKey((1n << 48n) - 2n, 0, randomValidPubKey()),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_AccountIsNotRegistered');
    });

    it('should success', async () => {
      await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);
      await changePubKey(zkLighter, receiver1, 0, randomValidPubKey());
    });
  });

  describe('CancelAllOrders', function () {
    it('should reverted', async () => {
      await expect(zkLighter.connect(receiver1).cancelAllOrders(15)).to.be.revertedWithCustomError(
        additionalZkLighter,
        'AdditionalZkLighter_AccountIsNotRegistered',
      );

      await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);

      await expect(zkLighter.connect(receiver1).cancelAllOrders(281474976710655)).to.be.revertedWithCustomError(
        additionalZkLighter,
        'AdditionalZkLighter_InvalidAccountIndex',
      );
    });

    it('should success', async () => {
      await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);
      await cancelAllOrders(zkLighter, receiver1);
    });
  });

  describe('CreateOrder', function () {
    it('should reverted', async () => {
      await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);

      await expect(
        zkLighter.connect(receiver1).createOrder(281474976710655, 1, 1, 1, 1, 1),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidAccountIndex');

      const index = await getAccountIndex(zkLighter, receiver1);

      // invalid isAsk
      await expect(zkLighter.connect(receiver1).createOrder(index, 1, 1, 1, 2, 1)).to.be.revertedWithCustomError(
        additionalZkLighter,
        'AdditionalZkLighter_InvalidCreateOrderParameters',
      );

      // invalid price
      await expect(zkLighter.connect(receiver1).createOrder(index, 1, 1, 0, 1, 1)).to.be.revertedWithCustomError(
        additionalZkLighter,
        'AdditionalZkLighter_InvalidCreateOrderParameters',
      );

      // invalid orderType
      await expect(zkLighter.connect(receiver1).createOrder(index, 1, 1, 1, 1, 2)).to.be.revertedWithCustomError(
        additionalZkLighter,
        'AdditionalZkLighter_InvalidCreateOrderParameters',
      );

      // invalid marketIndex
      await expect(zkLighter.connect(receiver1).createOrder(index, 2049, 1, 1, 1, 1)).to.be.revertedWithCustomError(
        additionalZkLighter,
        'AdditionalZkLighter_InvalidMarketType',
      );
    });

    it('should success', async () => {
      await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);
      await createOrder(zkLighter, receiver1, 1, 1, 1, 1, 1);
    });
  });

  describe('BurnShares', function () {
    it('should reverted', async () => {
      await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);

      const validPoolIndex = 140737488355328;

      await expect(
        zkLighter.connect(receiver1).burnShares(281474976710655, validPoolIndex, 1),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidAccountIndex');

      const index = await getAccountIndex(zkLighter, receiver1);

      // invalid pool index
      await expect(zkLighter.connect(receiver1).burnShares(index, 1, 1)).to.be.revertedWithCustomError(
        additionalZkLighter,
        'AdditionalZkLighter_InvalidAccountIndex',
      );

      await expect(zkLighter.connect(receiver1).burnShares(index, 281474976710655n, 1)).to.be.revertedWithCustomError(
        additionalZkLighter,
        'AdditionalZkLighter_InvalidAccountIndex',
      );

      await expect(zkLighter.connect(receiver1).burnShares(index, validPoolIndex, 0)).to.be.revertedWithCustomError(
        additionalZkLighter,
        'AdditionalZkLighter_InvalidShareAmount',
      );

      await expect(
        zkLighter.connect(receiver1).burnShares(index, validPoolIndex, 1152921504606846976n),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidShareAmount');
    });

    it('should success', async () => {
      await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);

      await burnShares(zkLighter, receiver1, 140737488355328, 5);
    });
  });

  describe('CreatePerpsMarket', function () {
    it('should create orderbook and emit `CreateMarket` event', async () => {
      const params = {
        marketIndex: 1n,
        quoteMultiplier: 1n,
        takerFee: 2n,
        makerFee: 1n,
        liquidationFee: 1n,
        minBaseAmount: 1n,
        minQuoteAmount: 1n,
        defaultInitialMarginFraction: 1n,
        minInitialMarginFraction: 1n,
        maintenanceMarginFraction: 1n,
        closeOutMarginFraction: 1n,
        interestRate: 1n,
        fundingClampSmall: 1n,
        fundingClampBig: 1n,
        openInterestLimit: 1n,
        orderQuoteLimit: 1n,
      };
      await createPerpsMarket(zkLighter, governorWallet, 3, 3, ethers.encodeBytes32String('BTC'), params);
    });

    it('should fail to create orderbook if market index is invalid', async () => {
      const params = emptyCreatePerpsMarket(255);

      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarketType');
    });

    it('should fail to create orderbook if market index is spot', async () => {
      const params = emptyCreatePerpsMarket(2049);

      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarketType');
    });

    it('should fail to create orderbook if quoteMultiplier is invalid', async () => {
      const params = emptyCreatePerpsMarket(1);
      params.rawMarketData.quoteMultiplier = 0;

      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidQuoteMultiplier');

      params.rawMarketData.quoteMultiplier = 1_000_000 + 1;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidQuoteMultiplier');
    });

    it('should fail to create orderbook if fees are invalid', async () => {
      const params = emptyCreatePerpsMarket(1);
      params.rawMarketData.quoteMultiplier = 1;

      params.rawMarketData.makerFee = 1_000_000 + 1;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidFeeAmount');

      params.rawMarketData.makerFee = 1;
      params.rawMarketData.takerFee = 1_000_000 + 1;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidFeeAmount');

      params.rawMarketData.makerFee = 1;
      params.rawMarketData.takerFee = 1;
      params.rawMarketData.liquidationFee = 1_000_000 + 1;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidFeeAmount');
    });

    it('should fail to create orderbook if margin requirements are invalid', async () => {
      const params = emptyCreatePerpsMarket(1);
      params.rawMarketData.quoteMultiplier = 1;

      params.rawMarketData.closeOutMarginFraction = 0;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarginFraction');

      params.rawMarketData.closeOutMarginFraction = 1;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarginFraction');

      params.rawMarketData.closeOutMarginFraction = 1;
      params.rawMarketData.maintenanceMarginFraction = 1;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarginFraction');

      params.rawMarketData.closeOutMarginFraction = 1;
      params.rawMarketData.maintenanceMarginFraction = 1;
      params.rawMarketData.minInitialMarginFraction = 1;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarginFraction');

      params.rawMarketData.closeOutMarginFraction = 1;
      params.rawMarketData.maintenanceMarginFraction = 1;
      params.rawMarketData.minInitialMarginFraction = 1;
      params.rawMarketData.defaultInitialMarginFraction = 10_000 + 1;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarginFraction');
    });

    it('should fail to create orderbook if interestRate is invalid', async () => {
      const params = emptyCreatePerpsMarket(1);
      params.rawMarketData.quoteMultiplier = 1;
      params.rawMarketData.closeOutMarginFraction = 1;
      params.rawMarketData.maintenanceMarginFraction = 1;
      params.rawMarketData.minInitialMarginFraction = 1;
      params.rawMarketData.defaultInitialMarginFraction = 1;
      params.rawMarketData.interestRate = 1_000_000 + 1;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidInterestRate');
    });

    it('should fail to create orderbook if min amounts are invalid', async () => {
      const params = emptyCreatePerpsMarket(1);
      params.rawMarketData.quoteMultiplier = 1;
      params.rawMarketData.closeOutMarginFraction = 1;
      params.rawMarketData.maintenanceMarginFraction = 1;
      params.rawMarketData.minInitialMarginFraction = 1;
      params.rawMarketData.defaultInitialMarginFraction = 1;
      params.rawMarketData.interestRate = 1;
      params.rawMarketData.minBaseAmount = 2 ** 48 - 1;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMinAmounts');

      params.rawMarketData.minBaseAmount = 1;
      params.rawMarketData.minQuoteAmount = 2 ** 48 - 1;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('BTC'), serializeCreatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidOrderQuoteLimit');
    });
  });

  describe('CreateSpotMarket', function () {
    it('should create orderbook and emit `CreateMarket` event', async () => {
      const params = {
        marketIndex: 2048n,
        baseAssetIndex: 1n,
        quoteAssetIndex: 3n,
        quoteMultiplier: 1n,
        sizeExtensionMultiplier: 1000000n,
        quoteExtensionMultiplier: 1000000n,
        takerFee: 2n,
        makerFee: 1n,
        minBaseAmount: 1n,
        minQuoteAmount: 1n,
        orderQuoteLimit: 1n,
      };
      await createSpotMarket(zkLighter, governorWallet, 3, 3, ethers.encodeBytes32String('ETH/USDC'), params);
    });

    it('should fail to create orderbook if assets are invalid', async () => {
      const params = emptyCreateSpotMarket(2049);
      params.rawMarketData.baseAssetIndex = 1n;
      params.rawMarketData.quoteAssetIndex = 1n;

      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidAssetIndex');

      params.rawMarketData.baseAssetIndex = 0n;
      params.rawMarketData.quoteAssetIndex = 1n;

      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidAssetIndex');

      params.rawMarketData.baseAssetIndex = 1n;
      params.rawMarketData.quoteAssetIndex = 59n;

      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidAssetIndex');
    });

    it('should fail to create orderbook if market index is invalid', async () => {
      const params = emptyCreateSpotMarket(255);

      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarketType');
    });

    it('should fail to create orderbook if market index is perps', async () => {
      const params = emptyCreateSpotMarket(1);

      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarketType');
    });

    it('should fail to create orderbook if ExtensionMultipliers are invalid', async () => {
      const params = emptyCreateSpotMarket(2049);
      params.rawMarketData.baseAssetIndex = 1n;
      params.rawMarketData.quoteAssetIndex = 3n;
      params.rawMarketData.quoteExtensionMultiplier = 0n;
      params.rawMarketData.sizeExtensionMultiplier = 1000000n;

      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidExtensionMultiplier');

      params.rawMarketData.quoteExtensionMultiplier = 1n;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidExtensionMultiplier');

      params.rawMarketData.quoteExtensionMultiplier = 1000000n;
      params.rawMarketData.sizeExtensionMultiplier = 0n;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidExtensionMultiplier');

      params.rawMarketData.sizeExtensionMultiplier = 1n;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidExtensionMultiplier');
    });

    it('should fail to create orderbook if fees are invalid', async () => {
      const params = emptyCreateSpotMarket(2049);
      params.rawMarketData.baseAssetIndex = 1n;
      params.rawMarketData.quoteAssetIndex = 3n;
      params.rawMarketData.quoteExtensionMultiplier = 1000000n;
      params.rawMarketData.sizeExtensionMultiplier = 1000000n;

      params.rawMarketData.makerFee = 1_000_001n;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidFeeAmount');

      params.rawMarketData.makerFee = 1n;
      params.rawMarketData.takerFee = 1_000_001n;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidFeeAmount');
    });

    it('should fail to create orderbook if min amounts are invalid', async () => {
      const params = emptyCreateSpotMarket(2049);
      params.rawMarketData.baseAssetIndex = 1n;
      params.rawMarketData.quoteAssetIndex = 3n;
      params.rawMarketData.quoteExtensionMultiplier = 1000000n;
      params.rawMarketData.sizeExtensionMultiplier = 1000000n;

      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMinAmounts');

      params.rawMarketData.minBaseAmount = 1;
      params.rawMarketData.minQuoteAmount = 2 ** 48 - 1;
      await expect(
        zkLighter
          .connect(governorWallet)
          .createMarket(1, 1, ethers.encodeBytes32String('ETH/USDC'), serializeCreateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidOrderQuoteLimit');
    });
  });

  describe('UpdateMarket', function () {
    it('should update orderbook and emit `UpdateMarket` event', async () => {
      await updatePerpsMarket(zkLighter, governorWallet, {
        marketIndex: 10n,
        status: 1n,
        takerFee: 0n,
        makerFee: 0n,
        liquidationFee: 0n,
        minBaseAmount: 1n,
        minQuoteAmount: 1n,
        defaultInitialMarginFraction: 1n,
        minInitialMarginFraction: 1n,
        maintenanceMarginFraction: 1n,
        closeOutMarginFraction: 1n,
        interestRate: 1n,
        fundingClampSmall: 1n,
        fundingClampBig: 1n,
        openInterestLimit: 1n,
        orderQuoteLimit: 1n,
      });
    });

    it('should fail to update orderbook if market index is invalid', async () => {
      const params = emptyUpdatePerpsMarket(255, 0);

      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarketType');
    });

    it('should fail to update orderbook if market index is spot', async () => {
      const params = emptyUpdatePerpsMarket(2049, 0);

      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarketType');
    });

    it('should fail to update orderbook if status is invalid', async () => {
      const params = emptyUpdatePerpsMarket(1, 3);

      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarketStatus');
    });

    it('should fail to update orderbook if fees are invalid', async () => {
      const params = emptyUpdatePerpsMarket(1, 0);

      params.rawMarketData.makerFee = 1_000_000 + 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidFeeAmount');

      params.rawMarketData.makerFee = 1;
      params.rawMarketData.takerFee = 1_000_000 + 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidFeeAmount');

      params.rawMarketData.makerFee = 1;
      params.rawMarketData.takerFee = 1;
      params.rawMarketData.liquidationFee = 1_000_000 + 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidFeeAmount');
    });

    it('should fail to update orderbook if margin requirements are invalid', async () => {
      const params = emptyUpdatePerpsMarket(1, 0);

      params.rawMarketData.closeOutMarginFraction = 0;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarginFraction');

      params.rawMarketData.closeOutMarginFraction = 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarginFraction');

      params.rawMarketData.closeOutMarginFraction = 1;
      params.rawMarketData.maintenanceMarginFraction = 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarginFraction');

      params.rawMarketData.closeOutMarginFraction = 1;
      params.rawMarketData.maintenanceMarginFraction = 1;
      params.rawMarketData.minInitialMarginFraction = 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarginFraction');

      params.rawMarketData.closeOutMarginFraction = 1;
      params.rawMarketData.maintenanceMarginFraction = 1;
      params.rawMarketData.minInitialMarginFraction = 1;
      params.rawMarketData.defaultInitialMarginFraction = 10_000 + 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarginFraction');
    });

    it('should fail to update orderbook if interestRate is invalid', async () => {
      const params = emptyUpdatePerpsMarket(1, 0);
      params.rawMarketData.closeOutMarginFraction = 1;
      params.rawMarketData.maintenanceMarginFraction = 1;
      params.rawMarketData.minInitialMarginFraction = 1;
      params.rawMarketData.defaultInitialMarginFraction = 1;

      params.rawMarketData.interestRate = 1_000_000 + 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidInterestRate');
    });

    it('should fail to update orderbook if min amounts are invalid', async () => {
      const params = emptyUpdatePerpsMarket(1, 0);
      params.rawMarketData.closeOutMarginFraction = 1;
      params.rawMarketData.maintenanceMarginFraction = 1;
      params.rawMarketData.minInitialMarginFraction = 1;
      params.rawMarketData.defaultInitialMarginFraction = 1;
      params.rawMarketData.interestRate = 1;

      params.rawMarketData.minBaseAmount = 2 ** 48 - 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMinAmounts');

      params.rawMarketData.minBaseAmount = 1;
      params.rawMarketData.minQuoteAmount = 2 ** 48 - 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdatePerpsMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidOrderQuoteLimit');
    });
  });

  describe('UpdateSpotMarket', function () {
    it('should update orderbook and emit `UpdateMarket` event', async () => {
      await updateSpotMarket(zkLighter, governorWallet, {
        marketIndex: 2049n,
        status: 1n,
        takerFee: 0n,
        makerFee: 0n,
        minBaseAmount: 1n,
        minQuoteAmount: 1n,
        orderQuoteLimit: 1n,
      });
    });

    it('should fail to update orderbook if market index is invalid', async () => {
      const params = emptyUpdateSpotMarket(255, 0);

      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarketType');
    });

    it('should fail to update orderbook if market index is perps', async () => {
      const params = emptyUpdateSpotMarket(1, 0);

      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarketType');
    });

    it('should fail to update orderbook if status is invalid', async () => {
      const params = emptyUpdateSpotMarket(2049, 3);

      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMarketStatus');
    });

    it('should fail to update orderbook if fees are invalid', async () => {
      const params = emptyUpdateSpotMarket(2049, 0);

      params.rawMarketData.makerFee = 1_000_000 + 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidFeeAmount');

      params.rawMarketData.makerFee = 1;
      params.rawMarketData.takerFee = 1_000_000 + 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidFeeAmount');
    });

    it('should fail to update orderbook if min amounts are invalid', async () => {
      const params = emptyUpdateSpotMarket(2049, 0);

      params.rawMarketData.minBaseAmount = 2 ** 48 - 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidMinAmounts');

      params.rawMarketData.minBaseAmount = 1;
      params.rawMarketData.minQuoteAmount = 2 ** 48 - 1;
      await expect(
        zkLighter.connect(governorWallet).updateMarket(serializeUpdateSpotMarket(params)),
      ).to.be.revertedWithCustomError(additionalZkLighter, 'AdditionalZkLighter_InvalidOrderQuoteLimit');
    });
  });

  describe('Activate Desert Mode', function () {
    it('should activate desert mode', async () => {
      await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);
      await createOrder(zkLighter, receiver1, 1, 1, 1, 1, 1);

      const openPriorityRequestCount = await zkLighter.openPriorityRequestCount();
      expect(openPriorityRequestCount).to.equal(2); // 1 deposit + 1 create order

      await incrementBlockstampBySeconds(15 * 24 * 60 * 60); // 15 days
      await advanceBlocks(10);

      let desertModeActivated = await zkLighter.desertMode();
      expect(desertModeActivated).to.be.false;

      const tx = await zkLighter.activateDesertMode();
      expect(tx).to.emit(zkLighter, 'DesertMode');

      desertModeActivated = await zkLighter.desertMode();
      expect(desertModeActivated).to.be.true;
    });

    it('should not activate desert mode if no priority request queued', async () => {
      const openPriorityRequestCount = await zkLighter.openPriorityRequestCount();
      expect(openPriorityRequestCount).to.equal(0);

      let desertModeActivated = await zkLighter.desertMode();
      expect(desertModeActivated).to.be.false;

      const tx = await zkLighter.activateDesertMode();
      await expect(tx).to.be.not.emit(zkLighter, 'DesertMode');

      desertModeActivated = await zkLighter.desertMode();
      expect(desertModeActivated).to.be.false;
    });

    it('should not activate desert mode if priority request is not expired', async () => {
      await depositUSDC(zkLighter, 10_000_000, usdc, sender1, receiver1);
      await createOrder(zkLighter, receiver1, 1, 1, 1, 1, 1);

      const openPriorityRequestCount = await zkLighter.openPriorityRequestCount();
      expect(openPriorityRequestCount).to.equal(2); // 1 deposit + 1 create order

      await incrementBlockstampBySeconds(13 * 24 * 60 * 60); // 13 days
      await advanceBlocks(10);

      let desertModeActivated = await zkLighter.desertMode();
      expect(desertModeActivated).to.be.false;

      const tx = await zkLighter.activateDesertMode();
      await expect(tx).to.be.not.emit(zkLighter, 'DesertMode');

      desertModeActivated = await zkLighter.desertMode();
      expect(desertModeActivated).to.be.false;
    });
  });

  // describe('Revert Blocks', function () {
  //   it('should can Revert fullExit operation', async () => {
  //     // register owner
  //     const erc20TxnData = await depositERC20(zkLighter, BigNumber.from(1000000), wbtcTokenId, wbtc, owner, owner);
  //     const erc20Receipt = await erc20TxnData.tx.wait();
  //     const erc20Event = erc20Receipt.events.find((event: any) => {
  //       return event.event === 'NewPriorityRequest';
  //     });
  //     const erc20PubData = erc20Event.args[3];

  //     // user request full exit, and get pubData
  //     const tx = await zkLighter.requestFullExit(ethers.constants.AddressZero);
  //     const receipt = await tx.wait();
  //     const event = receipt.events.find((event: any) => {
  //       return event.event === 'NewPriorityRequest';
  //     });
  //     const pubDataFullExit = event.args[3];

  //     const { newStateRoot, newValidiumRoot } = await getNewRoots(1);
  //     const commitBatch: CommitBatchInfo = {
  //       endBlockNumber: 1,
  //       batchSize: 1,
  //       timestamp: Date.now(),
  //       newStateRoot,
  //       newValidiumRoot,
  //       blocksPublicData: [
  //         ethers.utils.hexConcat([
  //           padEndBytes(erc20PubData, pubDataSizes[PubDataType.Deposit]),
  //           padEndBytes(pubDataFullExit, pubDataSizes[PubDataType.FullExit]),
  //         ]),
  //       ],
  //     };
  //     await expect(zkLighter.connect(validatorWallet).commitBatches([commitBatch], [genesisBatch]))
  //       .to.emit(zkLighter, 'BatchCommit')
  //       .withArgs(1, 1);

  //     let paddedPubDataSize = paddedPubDataSizes[PubDataType.Deposit] + paddedPubDataSizes[PubDataType.FullExit];
  //     if (paddedPubDataSize >= VERIFIER_MAX_FULL_CHUNK_SIZE) {
  //       paddedPubDataSize = VERIFIER_MAX_PUBDATA_SIZE;
  //     } else {
  //       paddedPubDataSize += ((64 - (paddedPubDataSize % 64)) % 64) + (VERIFIER_MAX_PUBDATA_SIZE % 64);
  //     }
  //     const paddedPubData = padEndBytes(
  //       ethers.utils.hexConcat([
  //         padEndBytes(erc20PubData, paddedPubDataSizes[PubDataType.Deposit]),
  //         padEndBytes(pubDataFullExit, paddedPubDataSizes[PubDataType.FullExit]),
  //       ]),
  //       paddedPubDataSize,
  //     );

  //     const revertBlockData = getStoredBatchInfo(commitBatch, paddedPubData, genesisBatch, 2, 0);
  //     const revertBlocksTxn = await zkLighter.connect(validatorWallet).revertBatches([revertBlockData]);
  //     await revertBlocksTxn.wait();
  //     const expectedTotalBlocksCommitted = 0;

  //     await expect(revertBlocksTxn).to.emit(zkLighter, 'BatchesRevert').withArgs(expectedTotalBlocksCommitted);
  //   });
  // });

  // describe('FullExit', function () {
  //   it('should successfully requestFullExit operation', async () => {
  //     // register owner
  //     const erc20TxnData = await depositERC20(zkLighter, BigNumber.from(1000000), wbtcTokenId, wbtc, owner, owner);
  //     const erc20Receipt = await erc20TxnData.tx.wait();
  //     const erc20Event = erc20Receipt.events.find((event: any) => {
  //       return event.event === 'NewPriorityRequest';
  //     });
  //     const erc20PubData = erc20Event.args[3];

  //     // user request full exit, and get pubData
  //     const tx = await zkLighter.requestFullExit(ethers.constants.AddressZero);
  //     const receipt = await tx.wait();
  //     const event = receipt.events.find((event: any) => {
  //       return event.event === 'NewPriorityRequest';
  //     });

  //     const pendingBalances = await zkLighter.getPendingBalances(owner.address, 0);
  //     const balanceToWithdraw = BigNumber.from(pendingBalances[0].toString());
  //     const reserveValue = BigNumber.from(pendingBalances[1].toString());

  //     expect(balanceToWithdraw).to.eq(BigNumber.from(0));
  //     expect(reserveValue).to.eq(FILLED_GAS_RESERVE_VALUE);

  //     const pubDataFullExit = event.args[3];
  //     const { newStateRoot, newValidiumRoot } = await getNewRoots(1);
  //     const commitBatch: CommitBatchInfo = {
  //       endBlockNumber: 1,
  //       batchSize: 1,
  //       timestamp: Date.now(),
  //       newStateRoot,
  //       newValidiumRoot,
  //       blocksPublicData: [
  //         ethers.utils.hexConcat([
  //           padEndBytes(erc20PubData, pubDataSizes[PubDataType.Deposit]),
  //           padEndBytes(pubDataFullExit, pubDataSizes[PubDataType.FullExit]),
  //         ]),
  //       ],
  //     };

  //     await expect(zkLighter.connect(validatorWallet).commitBatches([commitBatch], [genesisBatch]))
  //       .to.emit(zkLighter, 'BatchCommit')
  //       .withArgs(1, 1);
  //   });
  // });
});
