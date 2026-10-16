# Lighter EVM Devnet Contracts Preview

Preview of the contracts for Lighter EVM devnet, including L1 settlement, interoperability, and token gateways.

**These contracts have not undergone a production security process. They are a preview only and are NOT production-ready. Do not use them in production or with real funds.**

Please report security issues privately to [security@lighter.xyz](mailto:security@lighter.xyz).

## Build

Install [Foundry](https://getfoundry.sh/introduction/installation/), Node.js 20 or later, and [Yarn Classic](https://classic.yarnpkg.com/lang/en/docs/install/) 1.22.22. The build has been tested with Forge 1.8.0.

From a clone of this repository:

```sh
git submodule update --init lib/openvm-solidity-sdk
yarn install --frozen-lockfile
yarn build
```

## License

[Business Source License 1.1](LICENSE), unless a file's SPDX identifier specifies otherwise.

Third-party code and its licences are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
