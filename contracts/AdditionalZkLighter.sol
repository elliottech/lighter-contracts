// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IEvents.sol";
import "./lib/TxTypes.sol";
import "./Storage.sol";
import "./ExtendableStorage.sol";

/// @title zkLighter Additional Contract
/// @notice zkLighter Contract delegates some of its functionality to this contract
/// @author zkLighter Team
contract AdditionalZkLighter is IEvents, Storage, ReentrancyGuardUpgradeable, ExtendableStorage {
  error AdditionalZkLighter_Error();
  error AdditionalZkLighter_InvalidAssetIndex();
  error AdditionalZkLighter_InvalidDepositAmount();
  error AdditionalZkLighter_InvalidAccountIndex();
  error AdditionalZkLighter_AccountIsNotRegistered();
  error AdditionalZkLighter_OnlyCoreMessaging();
  error AdditionalZkLighter_InvalidCoreMessagingPubData();

  modifier onlyCoreMessaging() {
    if (msg.sender != coreMessaging) revert AdditionalZkLighter_OnlyCoreMessaging();
    _;
  }

  function updateStateRoot(
    StoredBatchInfo calldata _lastStoredBatch,
    bytes32 _stateRoot,
    bytes32 _validiumRoot,
    bytes calldata proof
  ) external nonReentrant onlyActive {
    governance.isActiveValidator(msg.sender);

    if (storedBatchHashes[committedBatchesCount] != hashStoredBatchInfo(_lastStoredBatch)) {
      revert AdditionalZkLighter_Error();
    }

    if (executedBatchesCount != committedBatchesCount) {
      revert AdditionalZkLighter_Error();
    }

    if (stateRootUpgradeVerifier != IZkLighterStateRootUpgradeVerifier(address(0))) {
      bytes32 hashOutput = keccak256(abi.encodePacked(stateRoot, validiumRoot, _stateRoot, _validiumRoot));

      uint256[] memory inputs = new uint256[](1);
      inputs[0] = uint256(hashOutput) % BN254_MODULUS;

      bool success = stateRootUpgradeVerifier.Verify(proof, inputs);
      if (!success) {
        revert AdditionalZkLighter_Error();
      }

      stateRootUpgradeVerifier = IZkLighterStateRootUpgradeVerifier(address(0));
    } else {
      revert AdditionalZkLighter_Error();
    }

    stateRoot = _stateRoot;
    validiumRoot = _validiumRoot;
    lastVerifiedStateRoot = _stateRoot;
    lastVerifiedValidiumRoot = _validiumRoot;
    stateRootUpdates[committedBatchesCount] = _stateRoot;

    emit StateRootUpdate(committedBatchesCount, _lastStoredBatch.stateRoot, _stateRoot);
  }

  /// @notice Deposit ETH or ERC20 asset to zkLighter
  /// @param _assetIndex Asset index
  /// @param _routeType Route type
  /// @param _amount ETH or ERC20 asset amount to deposit
  /// @param _to The receiver L1 address
  function _deposit(address[] memory _to, uint16 _assetIndex, TxTypes.RouteType _routeType, uint256[] memory _amount) internal {
    AssetConfig memory assetConfig = validateAndGetAssetConfig(_assetIndex);
    if (_assetIndex != NATIVE_ASSET_INDEX && msg.value != 0) {
      revert AdditionalZkLighter_InvalidDepositAmount();
    }

    uint256 minDeposit = uint256(assetConfig.minDepositTicks) * uint256(assetConfig.tickSize);
    uint256 depositCap = uint256(assetConfig.depositCapTicks) * uint256(assetConfig.tickSize);
    uint256 totalAmount = 0;
    for (uint256 i = 0; i < _amount.length; ++i) {
      totalAmount += _amount[i];
      if (_amount[i] < minDeposit || _amount[i] % assetConfig.tickSize != 0) {
        revert AdditionalZkLighter_InvalidDepositAmount();
      }
      if (_to[i] == address(0)) {
        revert AdditionalZkLighter_AccountIsNotRegistered();
      }
    }

    uint256 balanceAfter = 0;
    if (_assetIndex == NATIVE_ASSET_INDEX) {
      balanceAfter = address(this).balance;
      if (msg.value != totalAmount) {
        revert AdditionalZkLighter_InvalidDepositAmount();
      }
    } else {
      IERC20 _token = IERC20(assetConfig.tokenAddress);
      uint256 balanceBefore = _token.balanceOf(address(this));
      SafeERC20.safeTransferFrom(_token, msg.sender, address(this), totalAmount);
      balanceAfter = _token.balanceOf(address(this));
      if (balanceAfter < balanceBefore + totalAmount) {
        revert AdditionalZkLighter_InvalidDepositAmount();
      } else if (balanceAfter > balanceBefore + totalAmount) {
        uint256 excessAmount = balanceAfter - (balanceBefore + totalAmount);
        uint64 baseExcessAmount = SafeCast.toUint64(excessAmount / assetConfig.tickSize);
        increaseBalanceToWithdraw(TREASURY_ACCOUNT_INDEX, _assetIndex, baseExcessAmount);
      }
    }

    if (balanceAfter > depositCap) {
      revert AdditionalZkLighter_InvalidDepositAmount();
    }
    for (uint256 i = 0; i < _amount.length; ++i) {
      uint64 baseAmount = SafeCast.toUint64(_amount[i] / assetConfig.tickSize);
      registerDeposit(_to[i], _assetIndex, _routeType, baseAmount);
    }
  }

  /// @notice Deposit asset to Lighter
  /// @param _to The receiver L1 address
  /// @param _assetIndex Asset index
  /// @param _routeType Route type
  /// @param _amount asset amount to deposit
  function deposit(address _to, uint16 _assetIndex, TxTypes.RouteType _routeType, uint256 _amount) external payable nonReentrant onlyActive {
    uint256[] memory amount = new uint256[](1);
    amount[0] = _amount;
    address[] memory to = new address[](1);
    to[0] = _to;
    _deposit(to, _assetIndex, _routeType, amount);
  }

  /// @notice Deposit USDC to Lighter for multiple users
  /// @param _amount Array of USDC Token amounts
  /// @param _to Array of receiver L1 addresses
  /// @param _accountIndex Array of account index values, will be used in the future
  function depositBatch(uint64[] calldata _amount, address[] calldata _to, uint48[] calldata _accountIndex) external nonReentrant onlyActive {
    if (_amount.length != _to.length || _amount.length != _accountIndex.length || _amount.length == 0 || _amount.length > MAX_BATCH_DEPOSIT_LENGTH) {
      revert AdditionalZkLighter_Error();
    }
    uint256[] memory amount = new uint256[](_amount.length);
    for (uint256 i = 0; i < _amount.length; ++i) {
      amount[i] = uint256(_amount[i]);
    }
    _deposit(_to, USDC_ASSET_INDEX, TxTypes.RouteType.Perps, amount);
  }

  /// @notice Register deposit request - pack pubdata, add into onchainOpsCheck and emit OnchainDeposit event
  /// @param _toAddress Receiver Account's L1 address
  /// @param _assetIndex Asset index
  /// @param _routeType Route type
  /// @param _baseAmount Asset amount
  function registerDeposit(address _toAddress, uint16 _assetIndex, TxTypes.RouteType _routeType, uint64 _baseAmount) internal {
    uint48 _toAccountIndex = getAccountIndexFromAddress(_toAddress);
    // No account could be found for the address
    if (_toAccountIndex <= MAX_SYSTEM_ACCOUNT_INDEX) {
      _toAddress = address(0);
    } else if (_toAccountIndex == NIL_ACCOUNT_INDEX) {
      ++lastAccountIndex;
      _toAccountIndex = lastAccountIndex;
      if (_toAccountIndex > MAX_MASTER_ACCOUNT_INDEX) {
        revert AdditionalZkLighter_InvalidAccountIndex();
      }
      addressToAccountIndex[_toAddress] = _toAccountIndex;
    }
    bytes memory pubData = TxTypes.writeDepositPubDataForPriorityQueue({
      accountIndex: _toAccountIndex,
      toAddress: _toAddress,
      assetIndex: _assetIndex,
      routeType: _routeType,
      baseAmount: _baseAmount
    });
    addPriorityRequest(msg.sender, TxTypes.PriorityPubDataTypeL1Deposit, pubData, pubData);
    emit Deposit(_toAccountIndex, _toAddress, _assetIndex, _routeType, _baseAmount);
  }

  /// @notice Append a non-token Core request from L1CoreMessaging.
  function addPriorityRequestExt(
    address _sender,
    uint8 _pubdataType,
    bytes calldata _priorityRequest,
    bytes calldata _pubDataWithMetadata
  ) external nonReentrant onlyCoreMessaging onlyActive {
    if (
      _priorityRequest.length == 0 ||
      _priorityRequest.length > MAX_PRIORITY_REQUEST_PUBDATA_SIZE ||
      uint8(_priorityRequest[0]) != _pubdataType ||
      !_isCoreMessagingPubDataType(_pubdataType)
    ) {
      revert AdditionalZkLighter_InvalidCoreMessagingPubData();
    }
    addPriorityRequest(_sender, _pubdataType, _priorityRequest, _pubDataWithMetadata);
  }

  /// @dev Priority request types L1CoreMessaging is allowed to enqueue. Token-backed types (deposits) must never be accepted.
  function _isCoreMessagingPubDataType(uint8 _pubdataType) private pure returns (bool) {
    return
      _pubdataType == TxTypes.PriorityPubDataTypeL1ChangePubKey ||
      _pubdataType == TxTypes.PriorityPubDataTypeL1CreateMarket ||
      _pubdataType == TxTypes.PriorityPubDataTypeL1UpdateMarket ||
      _pubdataType == TxTypes.PriorityPubDataTypeL1CancelAllOrders ||
      _pubdataType == TxTypes.PriorityPubDataTypeL1Withdraw ||
      _pubdataType == TxTypes.PriorityPubDataTypeL1CreateOrder ||
      _pubdataType == TxTypes.PriorityPubDataTypeL1BurnShares ||
      _pubdataType == TxTypes.PriorityPubDataTypeL1RegisterAsset ||
      _pubdataType == TxTypes.PriorityPubDataTypeL1UpdateAsset ||
      _pubdataType == TxTypes.PriorityPubDataTypeL1SetSystemConfig ||
      _pubdataType == TxTypes.PriorityPubDataTypeL1ChangeECDSAPubKey;
  }

  /// @notice Saves priority request in storage
  /// @dev Calculates expiration timestamp of the request and stores the request in priorityRequests
  /// @param _pubdataType Priority request public data type
  /// @param _priorityRequest Request public data that is hashed and stored in priorityRequests
  /// @param _pubDataWithMetadata Request public data that is emitted in NewPriorityRequest event including the metadata
  function addPriorityRequest(address _sender, uint8 _pubdataType, bytes memory _priorityRequest, bytes memory _pubDataWithMetadata) internal {
    // Expiration timestamp is current block number + priority expiration delta
    uint64 expirationTimestamp = SafeCast.toUint64(block.timestamp + PRIORITY_EXPIRATION);
    uint64 nextPriorityRequestId = executedPriorityRequestCount + openPriorityRequestCount;
    bytes32 pubDataPrefix = bytes32(0);
    if (nextPriorityRequestId > 0) {
      pubDataPrefix = priorityRequests[nextPriorityRequestId - 1].prefixHash;
    }
    bytes memory paddedPubData = new bytes(MAX_PRIORITY_REQUEST_PUBDATA_SIZE);
    for (uint256 i = 0; i < _priorityRequest.length; ++i) {
      paddedPubData[i] = _priorityRequest[i];
    }
    priorityRequests[nextPriorityRequestId] = PriorityRequest({
      prefixHash: keccak256(abi.encodePacked(pubDataPrefix, paddedPubData)),
      expirationTimestamp: expirationTimestamp
    });
    emit NewPriorityRequest(_sender, nextPriorityRequestId, _pubdataType, _pubDataWithMetadata, expirationTimestamp);
    ++openPriorityRequestCount;
  }

  function increaseBalanceToWithdraw(uint48 _masterAccountIndex, uint16 _assetIndex, uint128 _baseAmount) internal {
    uint128 baseBalance = pendingAssetBalances[_assetIndex][_masterAccountIndex].balanceToWithdraw;
    pendingAssetBalances[_assetIndex][_masterAccountIndex] = PendingBalance(baseBalance + _baseAmount, FILLED_GAS_RESERVE_VALUE);
  }

  function validateAndGetAssetConfig(uint16 _assetIndex) internal view returns (AssetConfig memory) {
    AssetConfig memory assetConfig = assetConfigs[_assetIndex];
    if (_assetIndex != NATIVE_ASSET_INDEX && assetConfig.tokenAddress == address(0)) {
      revert AdditionalZkLighter_InvalidAssetIndex();
    }
    return assetConfig;
  }
}
