import { HardhatUserConfig } from 'hardhat/config';

import '@openzeppelin/hardhat-upgrades';
import 'hardhat-contract-sizer';

import * as dotenv from 'dotenv';
import { BigNumber } from '@ethersproject/bignumber';

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.25',
    settings: {
      evmVersion: 'cancun',
      optimizer: {
        enabled: true,
        runs: BigNumber.from(10).pow(3).toNumber(),
      },
      modelChecker: {
        engine: 'chc',
        divModNoSlacks: true,
        showUnproved: true,
        contracts: {
          'contracts/ZkLighter.sol': ['ZkLighter'],
          'contracts/AdditionalZkLighter.sol': ['AdditionalZkLighter'],
          'contracts/Governance.sol': ['Governance'],
        },
        invariants: ['contract', 'reentrancy'],
        targets: [
          'assert',
          'underflow',
          'overflow',
          'divByZero',
          'constantCondition',
          'popEmptyArray',
          'outOfBounds',
          'balance',
        ],
        timeout: 20000,
      },
      outputSelection: {
        '*': {
          '*': ['storageLayout'],
        },
      },
    },
  },
  paths: {
    root: '../',
  },
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      accounts: {
        accountsBalance: '10000000000000000000000000000000000000000',
      },
      hardfork: 'cancun',
    },
  },
};

export default config;
