// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {EVM_TO_L1_MESSENGER_ADDR} from "./Constants.sol";
import {IEvmToL1Messenger} from "./interfaces/IEvmToL1Messenger.sol";

/// @title SequencerFeeVault
/// @notice Accumulates EVM transaction fees at a fixed predeploy address.
/// Anyone can trigger a withdrawal of the full balance to the configured recipient.
/// @dev Modelled on Optimism's FeeVault (MIT):
/// https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts-bedrock/src/L2/FeeVault.sol
/// See THIRD_PARTY_NOTICES.md.
contract SequencerFeeVault {
    enum WithdrawalNetwork {
        EVM,
        L1
    }

    /// @custom:storage-location erc7201:lighter.storage.SequencerFeeVaultStorage
    struct SequencerFeeVaultStorage {
        address owner;
        address recipient;
        WithdrawalNetwork withdrawalNetwork;
        uint256 minWithdrawalAmount;
        uint256 totalProcessed;
    }

    event Withdrawal(address indexed from, address indexed to, uint256 value, WithdrawalNetwork withdrawalNetwork);
    event RecipientUpdated(address oldRecipient, address newRecipient);
    event MinWithdrawalAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event WithdrawalNetworkUpdated(WithdrawalNetwork oldNetwork, WithdrawalNetwork newNetwork);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    error SequencerFeeVault_AlreadyInitialized();
    error SequencerFeeVault_CallerNotAuthorized();
    error SequencerFeeVault_BelowMinimumWithdrawal();
    error SequencerFeeVault_ReentrantCall();
    error SequencerFeeVault_WithdrawalFailed();
    error SequencerFeeVault_ZeroAddress();

    // keccak256(abi.encode(uint256(keccak256("lighter.storage.SequencerFeeVaultStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant SequencerFeeVaultStorageLocation =
        0x2954e56424f34455c7d3faad2cd33e7269ffaeed1f847ff79ba56e8673abb900;

    uint256 private constant _REENTRANCY_TSLOT = 0x00;

    function _getSequencerFeeVaultStorage() private pure returns (SequencerFeeVaultStorage storage $) {
        assembly {
            $.slot := SequencerFeeVaultStorageLocation
        }
    }

    modifier nonReentrant() {
        bool locked;
        assembly {
            locked := tload(_REENTRANCY_TSLOT)
        }
        if (locked) revert SequencerFeeVault_ReentrantCall();
        assembly {
            tstore(_REENTRANCY_TSLOT, 1)
        }
        _;
        assembly {
            tstore(_REENTRANCY_TSLOT, 0)
        }
    }

    modifier onlyOwner() {
        if (msg.sender != _getSequencerFeeVaultStorage().owner) revert SequencerFeeVault_CallerNotAuthorized();
        _;
    }

    /// @notice Called once at genesis to configure the vault.
    /// @dev defaults to `WithdrawalNetwork.EVM`
    /// @dev Repeated calls blocked by `if ($.owner != address(0)) revert()` check
    function initialize(address owner_, address recipient_, uint256 minWithdrawalAmount_) external {
        SequencerFeeVaultStorage storage $ = _getSequencerFeeVaultStorage();
        if ($.owner != address(0)) revert SequencerFeeVault_AlreadyInitialized();
        if (owner_ == address(0)) revert SequencerFeeVault_ZeroAddress();
        if (recipient_ == address(0)) revert SequencerFeeVault_ZeroAddress();

        $.owner = owner_;
        $.recipient = recipient_;
        $.minWithdrawalAmount = minWithdrawalAmount_;
    }

    /// @notice Withdraws the full balance to the pre-configured recipient. Callable by anyone.
    function withdraw() external nonReentrant returns (uint256 value) {
        SequencerFeeVaultStorage storage $ = _getSequencerFeeVaultStorage();
        value = address(this).balance;
        if (value < $.minWithdrawalAmount) revert SequencerFeeVault_BelowMinimumWithdrawal();

        address recipient_ = $.recipient;
        if (recipient_ == address(0)) revert SequencerFeeVault_ZeroAddress();

        WithdrawalNetwork network = $.withdrawalNetwork;
        $.totalProcessed += value;
        emit Withdrawal(msg.sender, recipient_, value, network);

        if (network == WithdrawalNetwork.EVM) {
            (bool success,) = recipient_.call{value: value}("");
            if (!success) revert SequencerFeeVault_WithdrawalFailed();
        } else {
            IEvmToL1Messenger(EVM_TO_L1_MESSENGER_ADDR).initiateWithdrawal{value: value}(recipient_, hex"");
        }
    }

    function setRecipient(address newRecipient) external onlyOwner nonReentrant {
        if (newRecipient == address(0)) revert SequencerFeeVault_ZeroAddress();

        SequencerFeeVaultStorage storage $ = _getSequencerFeeVaultStorage();
        address oldRecipient = $.recipient;
        $.recipient = newRecipient;
        emit RecipientUpdated(oldRecipient, newRecipient);
    }

    function setMinWithdrawalAmount(uint256 newAmount) external onlyOwner nonReentrant {
        SequencerFeeVaultStorage storage $ = _getSequencerFeeVaultStorage();
        uint256 oldAmount = $.minWithdrawalAmount;
        $.minWithdrawalAmount = newAmount;
        emit MinWithdrawalAmountUpdated(oldAmount, newAmount);
    }

    function setWithdrawalNetwork(WithdrawalNetwork newNetwork) external onlyOwner nonReentrant {
        SequencerFeeVaultStorage storage $ = _getSequencerFeeVaultStorage();
        WithdrawalNetwork oldNetwork = $.withdrawalNetwork;
        $.withdrawalNetwork = newNetwork;
        emit WithdrawalNetworkUpdated(oldNetwork, newNetwork);
    }

    function transferOwnership(address newOwner) external onlyOwner nonReentrant {
        if (newOwner == address(0)) revert SequencerFeeVault_ZeroAddress();
        SequencerFeeVaultStorage storage $ = _getSequencerFeeVaultStorage();
        address oldOwner = $.owner;
        $.owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function owner() external view returns (address) {
        return _getSequencerFeeVaultStorage().owner;
    }

    function recipient() external view returns (address) {
        return _getSequencerFeeVaultStorage().recipient;
    }

    function minWithdrawalAmount() external view returns (uint256) {
        return _getSequencerFeeVaultStorage().minWithdrawalAmount;
    }

    function totalProcessed() external view returns (uint256) {
        return _getSequencerFeeVaultStorage().totalProcessed;
    }

    function withdrawalNetwork() external view returns (WithdrawalNetwork) {
        return _getSequencerFeeVaultStorage().withdrawalNetwork;
    }
}
