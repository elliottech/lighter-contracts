import { Contract } from 'ethers';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { ethers } from 'hardhat';
import { approveUSDC, genesisStateRoot, genesisValidiumRoot, transferFunds } from './util';
import { Governance } from '../../typechain-types';

export async function deployZkLighter(contractName: string) {
  const ZkLighter = await ethers.getContractFactory(contractName);

  const zkLighter = await ZkLighter.deploy();
  await zkLighter.waitForDeployment();

  return zkLighter;
}

export async function deployUSDC() {
  const factory = await ethers.getContractFactory('OwnableERC20');
  const contract = await factory.deploy('USDC', 'USDC', 6);
  await contract.waitForDeployment();
  return contract;
}

export async function deployMockGovernance() {
  const MockGovernance = await ethers.getContractFactory('GovernanceTest');
  const mockGovernance = await MockGovernance.deploy();
  await mockGovernance.waitForDeployment();

  return mockGovernance;
}

export async function deployAdditionalZkLighterImpl(): Promise<Contract> {
  const AdditionalZkLighter = await ethers.getContractFactory('AdditionalZkLighter');
  const additionalZkLighter = await AdditionalZkLighter.deploy();
  await additionalZkLighter.waitForDeployment();
  return additionalZkLighter;
}

export async function deployMockZkLighterProxy(initParams: string, implContract: Contract): Promise<Contract> {
  const Proxy = await ethers.getContractFactory('Proxy');
  const zkLighterProxy = await Proxy.deploy(await implContract.getAddress(), initParams);

  const ZkLighter = await ethers.getContractFactory('ZkLighterTest');
  const zkLighter = ZkLighter.attach(await zkLighterProxy.getAddress());
  return zkLighter;
}

export async function deployGovernanceImpl() {
  const Governance = await ethers.getContractFactory('Governance');
  const governance = await Governance.deploy();
  await governance.waitForDeployment();

  return governance;
}

export async function deployGovernanceProxy(initParams: string, implContract: Contract): Promise<Governance> {
  const governanceFactory = await ethers.getContractFactory('Governance');
  const Proxy = await ethers.getContractFactory('Proxy');

  const governanceProxy = await Proxy.deploy(await implContract.getAddress(), initParams);
  await governanceProxy.waitForDeployment();

  return governanceFactory.attach(await governanceProxy.getAddress()) as Governance;
}

export async function deployGovernance(governorAddress: string, usdcAddress: string): Promise<Governance> {
  const governanceImp = await deployGovernanceImpl();
  const governanceInitParams: string = ethers.AbiCoder.defaultAbiCoder().encode(
    ['address', 'address'],
    [governorAddress, usdcAddress],
  );

  return await deployGovernanceProxy(governanceInitParams, governanceImp);
}

export async function getExpirationTimestamp(zkLighter: Contract): Promise<number> {
  const currentBlockNumber = await ethers.provider.getBlockNumber();
  const currentBlockTimestamp = (await ethers.provider.getBlock(currentBlockNumber)).timestamp;
  const priorityExpiration = await zkLighter.PRIORITY_EXPIRATION();
  const expirationTimestamp = currentBlockTimestamp + parseInt(priorityExpiration, 10);
  return expirationTimestamp;
}

export async function getNextPriorityRequestId(zkLighter: Contract): Promise<number> {
  const executedPriorityRequestCount = await getTotalExecutedPriorityRequestId(zkLighter);
  const openPriorityRequestCount = await getTotalOpenPriorityRequests(zkLighter);
  return executedPriorityRequestCount + openPriorityRequestCount;
}

export async function getTotalExecutedPriorityRequestId(zkLighter: Contract): Promise<number> {
  const executedPriorityRequestCount = await zkLighter.executedPriorityRequestCount();
  return parseInt(executedPriorityRequestCount, 10);
}

export async function getTotalOpenPriorityRequests(zkLighter: Contract): Promise<number> {
  const openPriorityRequestCount = await zkLighter.openPriorityRequestCount();
  return parseInt(openPriorityRequestCount, 10);
}

export async function getZKLighterTestSetupValues() {
  return await loadFixture(_getZKLighterTestSetupValues);
}

async function _getZKLighterTestSetupValues() {
  const [owner, sender1, sender2, receiver1, receiver2, receiver3, receiver4, governorWallet, validatorWallet] =
    await ethers.getSigners();
  await transferFunds(owner, await governorWallet.getAddress(), '1000000');
  await transferFunds(owner, await sender1.getAddress(), '1000000');
  await transferFunds(owner, await sender2.getAddress(), '1000000');
  await transferFunds(owner, await validatorWallet.getAddress(), '1000000');

  const usdc = await deployUSDC();

  const governance: Contract = await deployGovernance(await governorWallet.getAddress(), await usdc.getAddress());

  const setValidatorTxn = await governance
    .connect(governorWallet)
    .setValidator(await validatorWallet.getAddress(), true);
  await setValidatorTxn.wait();

  const mockZkLighterVerifier = await (await ethers.getContractFactory('ZkLighterVerifierTest')).deploy();
  const mockDesertVerifier = await (await ethers.getContractFactory('DesertVerifierTest')).deploy();
  const additionalZkLighter: Contract = await deployAdditionalZkLighterImpl();
  const zkLighterImpl: Contract = await deployZkLighter('ZkLighterTest');

  const initParams = ethers.AbiCoder.defaultAbiCoder().encode(
    ['address', 'address', 'address', 'address', 'bytes32', 'bytes32'],
    [
      await governance.getAddress(), // _governanceAddress
      await mockZkLighterVerifier.getAddress(), // _verifierAddress
      await additionalZkLighter.getAddress(), // _additionalZkLighter
      await mockDesertVerifier.getAddress(), // _desertVerifier
      genesisStateRoot, // _genesisStateRoot
      genesisValidiumRoot, // _genesisValidiumRoot
    ],
  );

  const zkLighter: Contract = await deployMockZkLighterProxy(initParams, zkLighterImpl);

  await approveUSDC(owner, usdc, zkLighter, '2000000000000000');
  await approveUSDC(sender1, usdc, zkLighter, '200000000000000');
  await approveUSDC(sender2, usdc, zkLighter, '200000000000000');
  await approveUSDC(governorWallet, usdc, zkLighter, '200000000000000');
  await approveUSDC(receiver1, usdc, zkLighter, '200000000000000');
  await approveUSDC(receiver2, usdc, zkLighter, '200000000000000');
  await approveUSDC(receiver3, usdc, zkLighter, '200000000000000');

  return {
    owner,
    validatorWallet,
    zkLighter,
    zkLighterImpl,
    usdc,
    governance,
    mockZkLighterVerifier,
    additionalZkLighter,
    mockDesertVerifier,
    sender1,
    sender2,
    governorWallet,
    receiver1,
    receiver2,
    receiver3,
    receiver4,
  };
}
