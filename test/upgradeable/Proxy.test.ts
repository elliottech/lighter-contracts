import { ethers } from 'hardhat';
import {
  StoredBatchInfo,
  deployAdditionalZkLighterImpl,
  deployMockGovernance,
  deployUSDC,
  deployZkLighter,
} from '../shared';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Contract } from 'ethers';
import { expect } from 'chai';

describe('Proxy', function () {
  const _genesisStateRoot = '0x9138b1881fc37551cd6da339fd8b968bae7b3cc36ee78c857c4c0e9b923720dc';
  const _genesisValidiumRoot = '0xa96f8fe3b07701bc823ccaa874bb6c07e71823cf52c67eac12283b2ac142feac';

  let Proxy: Contract;
  let mockGovernance: Contract;
  let mockZkLighterVerifier: Contract;
  let mockDesertVerifier: Contract;
  let mockZkLighter: Contract;
  let mockAdditionalZkLighter: Contract;

  let proxyGovernance: Contract;
  let proxyZkLighterVerifier: Contract;
  let owner: SignerWithAddress, addr1: SignerWithAddress, addr2: SignerWithAddress, addr3: SignerWithAddress;

  let proxyZkLighter: Contract;

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.
  beforeEach(async function () {
    [owner, addr1, addr2, addr3] = await ethers.getSigners();

    const abi = ethers.AbiCoder.defaultAbiCoder();

    Proxy = await ethers.getContractFactory('Proxy');

    const usdc = await deployUSDC();

    mockGovernance = await deployMockGovernance();

    mockZkLighterVerifier = await (await ethers.getContractFactory('ZkLighterVerifierTest')).deploy();
    mockZkLighter = await deployZkLighter('ZkLighterTest');
    mockAdditionalZkLighter = await deployAdditionalZkLighterImpl();
    mockDesertVerifier = await (await ethers.getContractFactory('DesertVerifierTest')).deploy();

    proxyGovernance = await Proxy.deploy(
      await mockGovernance.getAddress(),
      abi.encode(['address', 'address'], [await owner.getAddress(), await usdc.getAddress()]),
    );
    await (
      await mockGovernance.attach(await proxyGovernance.getAddress())
    ).setValidator(await owner.getAddress(), true);

    proxyZkLighterVerifier = await Proxy.deploy(await mockZkLighterVerifier.getAddress(), await owner.getAddress());
    proxyZkLighter = await Proxy.deploy(
      await mockZkLighter.getAddress(),
      abi.encode(
        ['address', 'address', 'address', 'address', 'bytes32', 'bytes32'],
        [
          await proxyGovernance.getAddress(),
          await proxyZkLighterVerifier.getAddress(),
          await mockAdditionalZkLighter.getAddress(),
          await mockDesertVerifier.getAddress(),
          _genesisStateRoot,
          _genesisValidiumRoot,
        ],
      ),
    );
  });

  it('Proxy contract should store target address ', async function () {
    expect(await proxyGovernance.getTarget()).to.equal(await mockGovernance.getAddress());
    expect(await proxyZkLighterVerifier.getTarget()).to.equal(await mockZkLighterVerifier.getAddress());
    expect(await proxyZkLighter.getTarget()).to.equal(await mockZkLighter.getAddress());
  });

  describe('Proxy contract should upgrade new target', function () {
    it('upgrade new `Governance` target', async function () {
      const mockGovernanceNew = await deployMockGovernance();

      await proxyGovernance.upgradeTarget(await mockGovernanceNew.getAddress(), ethers.ZeroHash);
      expect(await proxyGovernance.getTarget()).to.equal(await mockGovernanceNew.getAddress());
    });

    it('upgradeTarget event', async function () {
      const mockGovernanceNew = await deployMockGovernance();

      const upgrade = await proxyGovernance.upgradeTarget(
        await mockGovernanceNew.getAddress(),
        await addr1.getAddress(),
      );
      const receipt = await upgrade.wait();
      const event = receipt.logs.filter(({ event }) => {
        return event === 'Upgraded';
      });

      expect(event[0]).to.be.not.null;
    });

    it('upgrade new `ZkLighterVerifier` target', async function () {
      const MockZkLighterVerifier = await ethers.getContractFactory('ZkLighterVerifierTest');
      const mockZkLighterVerifierNew = await MockZkLighterVerifier.deploy();
      await mockZkLighterVerifierNew.waitForDeployment();

      await proxyZkLighterVerifier.upgradeTarget(await mockZkLighterVerifierNew.getAddress(), ethers.ZeroHash);
      expect(await proxyZkLighterVerifier.getTarget()).to.equal(await mockZkLighterVerifierNew.getAddress());
    });
  });

  describe('Proxy contract should delegate function', function () {
    it('delegate `changeGovernor` function', async function () {
      // use Governance abi to call function in proxy address
      const implement = mockGovernance.attach(await proxyGovernance.getAddress());
      await implement.changeGovernor(await addr1.getAddress());

      expect(await implement.networkGovernor()).to.equal(await addr1.getAddress());
    });

    it('delegate `Verify` function', async function () {
      const implement = mockZkLighterVerifier.attach(await proxyZkLighterVerifier.getAddress());
      await implement.Verify(ethers.encodeBytes32String('proof'), [1]);
    });

    it('delegate `deposit` function', async function () {
      const implement = mockZkLighter.attach(await proxyZkLighter.getAddress()).connect(owner);
      await expect(implement.deposit(1_000_000, await addr1.getAddress())).to.be.revertedWith(
        'ERC20: insufficient allowance',
      );
    });

    it('delegate `revertBatches` function', async function () {
      const implement = mockZkLighter.attach(await proxyZkLighter.getAddress()).connect(owner);
      const batch = {
        batchNumber: 0,
        endBlockNumber: 0,
        batchSize: 0,
        startTimestamp: 0,
        endTimestamp: 0,
        priorityRequestCount: 0,
        prefixPriorityRequestHash: ethers.ZeroHash,
        onChainOperationsHash: ethers.ZeroHash,
        stateRoot: _genesisStateRoot,
        validiumRoot: _genesisValidiumRoot,
        commitment: ethers.ZeroHash,
      } as StoredBatchInfo;
      await implement.revertBatches([], batch);
    });
  });

  describe('Proxy contract should intercept upgrade function', function () {
    it('intercept `Governance` upgrade', async function () {
      const governanceImplement = mockGovernance.attach(await proxyGovernance.getAddress());
      await expect(governanceImplement.upgrade(await addr1.getAddress())).to.be.revertedWith('upg11');
    });

    it('intercept `ZkLighterVerifier` upgrade', async function () {
      const zkLighterVerifierImplement = mockZkLighterVerifier.attach(await proxyZkLighterVerifier.getAddress());
      await expect(zkLighterVerifierImplement.upgrade(await addr2.getAddress())).to.be.revertedWith('upg11');
    });

    it('intercept `ZkLighter` upgrade', async function () {
      const zkLighterImplement = mockZkLighter.attach(await proxyZkLighter.getAddress());
      await expect(zkLighterImplement.upgrade(await addr3.getAddress())).to.be.revertedWith('upg11');
    });
  });

  describe('Destruct logic contract with `upgrade` method', function () {
    it('deploy ZkLighter', async function () {
      expect(await proxyZkLighter.getTarget()).to.equal(await mockZkLighter.getAddress());
    });

    it.skip('upgrade zkLighter', async function () {
      const attackerContract = await deployAdditionalZkLighterImpl();
      const upgradeParams = ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'address'],
        [await attackerContract.getAddress(), await mockDesertVerifier.getAddress()],
      );

      await expect(mockZkLighter.upgrade(upgradeParams)).to.be.revertedWithCustomError(
        mockZkLighter,
        'ZkLighter_OnlyProxyCanCallUpgrade',
      );
      await proxyZkLighter.upgradeTarget(await mockZkLighter.getAddress(), upgradeParams);
    });

    it('invoking `upgrade` bypassing proxy should be intercepted', async function () {
      const attackerContract = await deployAdditionalZkLighterImpl();
      const upgradeParams = ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'address'],
        [await attackerContract.getAddress(), await mockDesertVerifier.getAddress()],
      );

      await expect(mockZkLighter.upgrade(upgradeParams)).to.be.revertedWithCustomError(
        mockZkLighter,
        'ZkLighter_OnlyProxyCanCallUpgrade',
      );

      // calls bypassing proxy contract should be intercepted
      await expect(mockZkLighter.deposit(10, await addr1.getAddress())).to.be.revertedWithCustomError(
        mockZkLighter,
        'ZkLighter_ImplCantDelegateToAddl',
      );
    });
  });
});
