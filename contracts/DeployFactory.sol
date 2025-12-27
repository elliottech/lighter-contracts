// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "./interfaces/IGovernance.sol";
import "./AdditionalZkLighter.sol";
import "./proxy/Proxy.sol";
import "./proxy/UpgradeGatekeeper.sol";

/// @title Deploy Factory Contract
/// @author zkLighter Team
contract DeployFactory {
  /// @notice Thrown when address of an element in address array in constructor is zero
  error ZkLighter_DeployFactory_AddressCannotBeZero();

  /// @notice Thrown when address array in constructor arguments are of wrong length
  error ZkLighter_DeployFactory_WrongAddressLength();

  Proxy governance;
  Proxy verifier;
  Proxy zkLighter;

  struct DeployedContractAddress {
    address governanceTarget;
    address verifierTarget;
    address zkLighterTarget;
    address validator;
    address governor;
    address desertVerifier;
    address securityCouncilAddress;
    address usdc;
  }

  struct AdditionalParams {
    bytes32 genesisStateRoot;
    bytes32 genesisValidiumRoot;
  }

  event Addresses(address governance, address verifier, address zkLighter, address gatekeeper, address additionalZkLighter);

  constructor(address[] memory addrs, bytes32 _genesisStateRoot, bytes32 _genesisValidiumRoot) {
    if (addrs.length != 8) {
      revert ZkLighter_DeployFactory_WrongAddressLength();
    }

    for (uint256 i = 0; i < addrs.length; ++i) {
      if (addrs[i] == address(0)) {
        revert ZkLighter_DeployFactory_AddressCannotBeZero();
      }
    }

    // Package all contract address to struct for avoiding StackTooDeep
    DeployedContractAddress memory contracts = DeployedContractAddress({
      governanceTarget: addrs[0],
      verifierTarget: addrs[1],
      zkLighterTarget: addrs[2],
      validator: addrs[3],
      governor: addrs[4],
      desertVerifier: addrs[5],
      securityCouncilAddress: addrs[6],
      usdc: addrs[7]
    });

    AdditionalParams memory params = AdditionalParams({genesisStateRoot: _genesisStateRoot, genesisValidiumRoot: _genesisValidiumRoot});

    deployProxyContracts(contracts, params);
  }

  function deployProxyContracts(DeployedContractAddress memory _contracts, AdditionalParams memory _additionalParams) internal {
    AdditionalZkLighter additionalZkLighter = new AdditionalZkLighter();

    // Deploy proxy contracts
    governance = new Proxy(address(_contracts.governanceTarget), abi.encode(this, _contracts.usdc));
    verifier = new Proxy(address(_contracts.verifierTarget), abi.encode());
    zkLighter = new Proxy(
      address(_contracts.zkLighterTarget),
      abi.encode(
        address(governance),
        address(verifier),
        address(additionalZkLighter),
        _contracts.desertVerifier,
        _additionalParams.genesisStateRoot,
        _additionalParams.genesisValidiumRoot
      )
    );

    // Deploy upgrade gatekeeper
    UpgradeGatekeeper upgradeGatekeeper = new UpgradeGatekeeper(_contracts.securityCouncilAddress, address(zkLighter));

    // Transfer mastership and add upgradeable
    governance.transferMastership(address(upgradeGatekeeper));
    upgradeGatekeeper.addUpgradeable(address(governance));

    verifier.transferMastership(address(upgradeGatekeeper));
    upgradeGatekeeper.addUpgradeable(address(verifier));

    zkLighter.transferMastership(address(upgradeGatekeeper));
    upgradeGatekeeper.addUpgradeable(address(zkLighter));

    upgradeGatekeeper.transferMastership(_contracts.governor);

    // Emit addresses
    emit Addresses(address(governance), address(verifier), address(zkLighter), address(upgradeGatekeeper), address(additionalZkLighter));

    // Set governance
    IGovernance governanceInstance = IGovernance(address(governance));
    governanceInstance.setValidator(_contracts.validator, true);
    governanceInstance.changeGovernor(_contracts.governor);
  }
}
