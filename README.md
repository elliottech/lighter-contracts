# Lighter Contracts

## Getting Started

### Prerequisites
- [Node.js](https://nodejs.org/en/download/) (v20)
- [Yarn](https://yarnpkg.com/getting-started/install)
- [Foundry](https://getfoundry.sh/)

### build && test
```shell
yarn build
yarn run hardhat test
forge test --vvv
```

### deploy to local geth/reth
```shell
yarn build
yarn deploy:local
yarn deposit:local
```

### deploy to non-local environments

Use `--config deploy.hardhat.config.ts` to deploy to other environments, such as testnet or mainnet.

## License

`lighter-contracts` is released under the Business Source License 1.1
