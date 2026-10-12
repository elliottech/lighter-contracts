import { HardhatUserConfig } from 'hardhat/config';

import '@nomicfoundation/hardhat-toolbox';
import '@openzeppelin/hardhat-upgrades';
import '@nomicfoundation/hardhat-foundry';
import 'hardhat-abi-exporter';
import 'hardhat-contract-sizer';
import * as dotenv from 'dotenv';
import { BigNumber } from '@ethersproject/bignumber';

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.25',
    settings: {
      viaIR: true,
      evmVersion: 'cancun',
      optimizer: {
        enabled: true,
        runs: BigNumber.from(10).pow(3).toNumber(),
      },
      outputSelection: {
        '*': {
          '*': ['storageLayout'],
        },
      },
    },
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

    gethLocalNode: {
      url: 'http://127.0.0.1:8545',
      accounts: [
        '59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
        'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        '5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a',
        '7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6',
      ],
      timeout: 300000,
      gas: 10000000,
    },
  },

  abiExporter: {
    path: './abi',
    clear: true,
    flat: true,
    only: [':Governance$', ':ZkLighter', ':StablePriceOracle'],
    spacing: 2,
  },

  contractSizer: {
    alphaSort: true,
    disambiguatePaths: false,
    runOnCompile: true,
    strict: false,
  },
};

export default config;
