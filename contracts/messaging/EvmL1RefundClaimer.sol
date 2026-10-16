// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {EVM_INTEROP_MANAGER_ADDR, EVM_REPLAYABLE_MESSENGER_ADDR, LIGHTER_CORE_SYSTEM_ADDR} from "../Constants.sol";
import {IEvmReplayableMessenger} from "../interfaces/IEvmReplayableMessenger.sol";
import {EvmInteropManager} from "../interop/EvmInteropManager.sol";
import {Config} from "../Config.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract EvmL1RefundClaimer is Config {
  using SafeERC20 for IERC20;

  error EvmL1RefundClaimer_CallerNotAuthorized();
  error EvmL1RefundClaimer_ClaimNonceMismatch();
  error EvmL1RefundClaimer_InvalidInitiator();
  error EvmL1RefundClaimer_InsufficientClaim();
  error EvmL1RefundClaimer_InvalidBaseAmount();
  error EvmL1RefundClaimer_RecipientAddressInvalid();
  error EvmL1RefundClaimer_ReentrantCall();
  error EvmL1RefundClaimer_EthTransferFailed();
  error EvmL1RefundClaimer_UnexpectedMsgValue();

  event L1AccountRefundCredited(uint32 indexed assetIndex, address indexed l1Address, uint128 baseAmount);
  event L1AccountRefundClaimed(uint32 indexed assetIndex, address indexed l1Address, address indexed recipient, uint256 baseAmount);

  struct ClaimData {
    uint128 baseAmount;
    uint64 claimNonce;
  }

  /// @custom:storage-location erc7201:lighter.storage.EvmL1RefundClaimer
  struct EvmL1RefundClaimerStorage {
    mapping(address l1Address => mapping(uint32 assetIndex => ClaimData claimData)) claims;
  }

  // keccak256(abi.encode(uint256(keccak256("lighter.storage.EvmL1RefundClaimer")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant EvmL1RefundClaimerStorageLocation = 0x2e87e7e43511ae9322306915a12ec0e80d4f08f6055ec7ce97cd19ec13b4ba00;

  function _getEvmL1RefundClaimerStorage() private pure returns (EvmL1RefundClaimerStorage storage $) {
    assembly {
      $.slot := EvmL1RefundClaimerStorageLocation
    }
  }

  uint256 private constant _REENTRANCY_TSLOT = 0x00;

  modifier nonReentrant() {
    bool locked;
    assembly {
      locked := tload(_REENTRANCY_TSLOT)
    }
    if (locked) revert EvmL1RefundClaimer_ReentrantCall();
    assembly {
      tstore(_REENTRANCY_TSLOT, 1)
    }
    _;
    assembly {
      tstore(_REENTRANCY_TSLOT, 0)
    }
  }

  function claims(address l1Address, uint32 assetIndex) external view returns (uint256 baseAmount) {
    return _getEvmL1RefundClaimerStorage().claims[l1Address][assetIndex].baseAmount;
  }

  function claimNonces(address l1Address, uint32 assetIndex) external view returns (uint64 claimNonce) {
    return _getEvmL1RefundClaimerStorage().claims[l1Address][assetIndex].claimNonce;
  }

  /// @dev ERC-20s will route through the `EvmInteropManager` so that the tokens
  /// can be held by this contract.
  function creditClaimFromCore(address l1Address, uint32 assetIndex, uint128 baseAmount) external nonReentrant {
    if (msg.sender != EVM_INTEROP_MANAGER_ADDR) revert EvmL1RefundClaimer_CallerNotAuthorized();
    if (tx.origin != LIGHTER_CORE_SYSTEM_ADDR) revert EvmL1RefundClaimer_InvalidInitiator();
    if (baseAmount == 0) revert EvmL1RefundClaimer_InvalidBaseAmount();

    EvmL1RefundClaimerStorage storage $ = _getEvmL1RefundClaimerStorage();
    $.claims[l1Address][assetIndex].baseAmount += baseAmount;

    emit L1AccountRefundCredited(assetIndex, l1Address, baseAmount);
  }

  /// @dev ETH refunds will be routed directly to this contract.
  function receiveL1AccountRefund(address l1Address, uint32 assetIndex, uint128 baseAmount) external payable nonReentrant {
    if (msg.sender != LIGHTER_CORE_SYSTEM_ADDR) revert EvmL1RefundClaimer_CallerNotAuthorized();
    if (baseAmount == 0) revert EvmL1RefundClaimer_InvalidBaseAmount();

    EvmInteropManager.CoreAssetEvmConfig memory assetConfig = EvmInteropManager(EVM_INTEROP_MANAGER_ADDR).getAssetConfig(assetIndex);
    assert(assetIndex == NATIVE_ASSET_INDEX);
    assert(assetConfig.tickSize != 0);
    assert(assetConfig.evmToken == ETH_ADDRESS);

    uint256 amount = uint256(baseAmount) * uint256(assetConfig.tickSize);
    if (msg.value != amount) revert EvmL1RefundClaimer_UnexpectedMsgValue();

    EvmL1RefundClaimerStorage storage $ = _getEvmL1RefundClaimerStorage();
    $.claims[l1Address][assetIndex].baseAmount += baseAmount;

    emit L1AccountRefundCredited(assetIndex, l1Address, baseAmount);
  }

  function claimTo(uint32 assetIndex, uint64 claimNonce, address recipient) external nonReentrant {
    if (msg.sender != EVM_REPLAYABLE_MESSENGER_ADDR) revert EvmL1RefundClaimer_CallerNotAuthorized();
    if (recipient == address(0)) revert EvmL1RefundClaimer_RecipientAddressInvalid();

    address l1Address = IEvmReplayableMessenger(EVM_REPLAYABLE_MESSENGER_ADDR).xDomainSender();

    EvmL1RefundClaimerStorage storage $ = _getEvmL1RefundClaimerStorage();
    ClaimData storage claimData = $.claims[l1Address][assetIndex];
    if (claimData.claimNonce != claimNonce) revert EvmL1RefundClaimer_ClaimNonceMismatch();

    uint128 currentClaim = claimData.baseAmount;
    if (currentClaim == 0) revert EvmL1RefundClaimer_InsufficientClaim();

    claimData.baseAmount = 0;
    unchecked {
      claimData.claimNonce = claimNonce + 1;
    }

    EvmInteropManager.CoreAssetEvmConfig memory assetConfig = EvmInteropManager(EVM_INTEROP_MANAGER_ADDR).getAssetConfig(assetIndex);
    assert(assetConfig.tickSize != 0);
    uint256 amount = uint256(currentClaim) * uint256(assetConfig.tickSize);

    if (assetIndex == NATIVE_ASSET_INDEX) {
      assert(assetConfig.evmToken == ETH_ADDRESS);

      (bool success, ) = recipient.call{value: amount}("");
      if (!success) revert EvmL1RefundClaimer_EthTransferFailed();
    } else {
      assert(assetConfig.evmToken != address(0));
      IERC20(assetConfig.evmToken).safeTransfer(recipient, amount);
    }

    emit L1AccountRefundClaimed(assetIndex, l1Address, recipient, currentClaim);
  }
}
