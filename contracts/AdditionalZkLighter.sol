// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./interfaces/IEvents.sol";
import "./interfaces/IZkLighter.sol";
import {IL1CoreMessaging} from "./interfaces/IL1CoreMessaging.sol";
import "./lib/TxTypes.sol";
import "./Storage.sol";
import "./ExtendableStorage.sol";
import {L2_SENDER_TOFFSET} from "./Constants.sol";

/// @title zkLighter Additional Contract
/// @notice zkLighter Contract delegates some of its functionality to this contract
/// @author zkLighter Team
contract AdditionalZkLighter is IEvents, Storage, ReentrancyGuardUpgradeable, ExtendableStorage {
  error AdditionalZkLighter_Error();
  error AdditionalZkLighter_InvalidStateRootPreimage();
  error AdditionalZkLighter_OnlyCoreMessaging();
  error AdditionalZkLighter_L1CallHashNotReady();
  error AdditionalZkLighter_L1CallHashAlreadyExists();
  error AdditionalZkLighter_L1CallAlreadyFulfilled();
  error AdditionalZkLighter_L2SenderNotZero();
  error AdditionalZkLighter_CannotExecuteToSelf();
  error AdditionalZkLighter_L1CallFailed();
  error AdditionalZkLighter_BatchNotExecuted();
  error AdditionalZkLighter_NoEvmL1CallsRoot();
  error AdditionalZkLighter_InvalidEvmL1CallProof();
  error AdditionalZkLighter_InvalidPubdataLength();
  error AdditionalZkLighter_CannotCreateWithRecipient();
  error AdditionalZkLighter_GasLimitTooHigh();
  error AdditionalZkLighter_GasLimitTooLow();
  error AdditionalZkLighter_InitcodeTooLarge();
  error AdditionalZkLighter_InsufficientMsgValue();
  error AdditionalZkLighter_RefundFailed();
  error AdditionalZkLighter_FeeTransferFailed();

  event NewEvmPriorityRequest(
    uint64 indexed requestId,
    address indexed sender,
    address indexed to,
    uint256 mintAmount,
    uint256 value,
    uint256 gasLimit,
    bool isCreation,
    bytes data,
    uint64 expirationTimestamp,
    bytes32 prefixHash
  );

  uint256 private constant INTRINSIC_GAS_TX = 21_000;

  uint256 private constant INTRINSIC_GAS_CONTRACT_CREATION = 32_000;

  /// @dev EIP-7825 transaction gas ceiling enforced by the EVM.
  uint32 private constant MAX_EVM_TX_GAS_LIMIT = 2 ** 24;

  /// @dev EIP-3860 maximum initcode size.
  uint256 private constant MAX_INITCODE_SIZE = 49_152;

  /// @dev EIP-7623 floor gas.
  uint256 private constant GAS_PER_BYTE = 40;

  uint160 internal constant OFFSET = uint160(0x1111000000000000000000000000000000001111);

  modifier onlyCoreMessaging() {
    if (msg.sender != coreMessaging) revert AdditionalZkLighter_OnlyCoreMessaging();
    _;
  }

  function updateCoreStateRoot(
    StoredBatchInfo calldata _lastStoredBatch,
    IZkLighter.LighterStateRootPreimage calldata stateRootPreimage,
    bytes32 newCoreStateRoot,
    bytes32 newValidiumRoot,
    bytes calldata proof
  ) external nonReentrant onlyActive {
    governance.isActiveValidator(msg.sender);

    if (storedBatchHashes[committedBatchesCount] != hashStoredBatchInfo(_lastStoredBatch)) {
      revert AdditionalZkLighter_Error();
    }

    if (executedBatchesCount != committedBatchesCount) {
      revert AdditionalZkLighter_Error();
    }

    if (_computeLighterStateRoot(stateRootPreimage, coreStateRoot) != stateRoot) {
      revert AdditionalZkLighter_InvalidStateRootPreimage();
    }
    bytes32 newLighterStateRoot = _computeLighterStateRoot(stateRootPreimage, newCoreStateRoot);

    if (stateRootUpgradeVerifier != IZkLighterStateRootUpgradeVerifier(address(0))) {
      bytes32 hashOutput = keccak256(abi.encodePacked(stateRoot, validiumRoot, newLighterStateRoot, newValidiumRoot));

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

    stateRoot = newLighterStateRoot;
    coreStateRoot = newCoreStateRoot;
    validiumRoot = newValidiumRoot;
    lastVerifiedStateRoot = newLighterStateRoot;
    lastVerifiedCoreStateRoot = newCoreStateRoot;
    lastVerifiedValidiumRoot = newValidiumRoot;
    stateRootUpdates[committedBatchesCount] = newLighterStateRoot;

    emit StateRootUpdate(committedBatchesCount, _lastStoredBatch.commitBatchInfo.newStateRoot, newLighterStateRoot);
  }

  function _computeLighterStateRoot(
    IZkLighter.LighterStateRootPreimage calldata stateRootPreimage,
    bytes32 coreStateRoot_
  ) internal pure returns (bytes32) {
    return
      keccak256(
        abi.encodePacked(
          stateRootPreimage.evmBlockHash,
          coreStateRoot_,
          stateRootPreimage.toEvmWriteStreamRoot,
          stateRootPreimage.toCoreWriteStreamRoot,
          stateRootPreimage.latestParentCoreBlockNumber
        )
      );
  }

  /// @notice Saves priority request in storage
  /// @dev Calculates expiration timestamp of the request and stores the request in priorityRequests
  /// @param _pubdataType Priority request public data type
  /// @param _priorityRequest Request public data that is hashed and stored in priorityRequests
  /// @param _pubDataWithMetadata Request public data that is emitted in NewPriorityRequest event including the metadata
  function addPriorityRequest(address _sender, uint8 _pubdataType, bytes calldata _priorityRequest, bytes calldata _pubDataWithMetadata) internal {
    uint256 pubDataLen = _priorityRequest.length;
    if (pubDataLen == 0 || pubDataLen > MAX_PRIORITY_REQUEST_PUBDATA_SIZE) {
      revert AdditionalZkLighter_InvalidPubdataLength();
    }

    // Expiration timestamp is current block number + priority expiration delta
    uint64 expirationTimestamp = SafeCast.toUint64(block.timestamp + PRIORITY_EXPIRATION);
    uint64 nextPriorityRequestId = executedPriorityRequestCount + openPriorityRequestCount;
    bytes32 pubDataPrefix = bytes32(0);
    if (nextPriorityRequestId > 0) {
      pubDataPrefix = priorityRequests[nextPriorityRequestId - 1].prefixHash;
    }
    priorityRequests[nextPriorityRequestId] = PriorityRequest({
      prefixHash: _hashPubDataPrefixed(pubDataPrefix, _priorityRequest),
      expirationTimestamp: expirationTimestamp
    });
    emit NewPriorityRequest(_sender, nextPriorityRequestId, _pubdataType, _pubDataWithMetadata, expirationTimestamp);
    ++openPriorityRequestCount;
  }

  /// @dev External entry point to the internal `addPriorityRequest`
  /// function. Only callable by L1CoreMessaging, which performs the
  /// action-specific access control and validation before calling it.
  function addPriorityRequestExt(
    address _sender,
    uint8 _pubdataType,
    bytes calldata _priorityRequest,
    bytes calldata _pubDataWithMetadata
  ) external payable onlyCoreMessaging {
    addPriorityRequest(_sender, _pubdataType, _priorityRequest, _pubDataWithMetadata);
  }

  /// @notice Deposits (msg.value) are guaranteed to land in the (potentially
  /// aliased) `msg.sender` address.
  ///
  /// @dev Fee for just depositing ETH can be bypassed by depositing to Core and
  /// transferring.
  function addEvmPriorityRequest(
    address to,
    uint256 value,
    uint256 depositAmount,
    uint256 gasLimit,
    bool isCreation,
    address refundAddress,
    bytes memory data
  ) external payable {
    if (isCreation) {
      if (to != address(0)) revert AdditionalZkLighter_CannotCreateWithRecipient();
      if (data.length > MAX_INITCODE_SIZE) revert AdditionalZkLighter_InitcodeTooLarge();
    }

    _validateGasLimit({gasLimit: gasLimit, dataLength: data.length, isCreation: isCreation});

    uint256 fee = computePriorityFee(gasLimit);
    if (msg.value < fee + depositAmount) revert AdditionalZkLighter_InsufficientMsgValue();

    address sender = msg.sender;
    if (sender != tx.origin) {
      // If sender is a classic SCA, then we apply address aliasing.
      // If sender is an EOA with no code, no aliasing is applied.
      // If sender is an EIP-7702 delegated EOA, then aliasing behavior depends on which wallet initiated the call.
      sender = _applyL1ToL2Alias(sender);
    }

    uint64 nextEvmPriorityRequestId = _nextEvmPriorityRequestId();
    bytes32 prefixHash;
    {
      bytes32 pubDataPrefix;
      if (nextEvmPriorityRequestId > 0) {
        pubDataPrefix = evmPriorityRequests[nextEvmPriorityRequestId - 1].prefixHash;
      }
      prefixHash = keccak256(abi.encodePacked(pubDataPrefix, sender, to, depositAmount, value, gasLimit, isCreation, data));
    }

    // Unsafe cast OK
    uint64 expirationTimestamp = uint64(block.timestamp + PRIORITY_EXPIRATION);
    evmPriorityRequests[nextEvmPriorityRequestId] = PriorityRequest({prefixHash: prefixHash, expirationTimestamp: expirationTimestamp});

    emit NewEvmPriorityRequest(
      nextEvmPriorityRequestId,
      sender,
      to,
      depositAmount,
      value,
      gasLimit,
      isCreation,
      data,
      expirationTimestamp,
      prefixHash
    );

    unchecked {
      ++openEvmPriorityRequestCount;
      uint256 refundAmount = msg.value - fee - depositAmount;
      if (refundAmount != 0) {
        (bool success, ) = refundAddress.call{value: refundAmount}(hex"");
        if (!success) revert AdditionalZkLighter_RefundFailed();
      }
    }

    address currentTreasury = IL1CoreMessaging(coreMessaging).getSystemAddress(TREASURY_ACCOUNT_INDEX);
    (bool success2, ) = currentTreasury.call{value: fee}("");
    if (!success2) revert AdditionalZkLighter_FeeTransferFailed();
  }

  /// @notice Fulfills a Core-originated L1 call whose hash was persisted by batch
  /// execution (`OnChainPubDataType.L1Call`). This operation is
  /// natively replayable -- if the transaction fails, it can be retried.
  ///
  /// @param _l2Sender The initiator of the transaction on the L2 side.
  /// @param to The target of the L1 transaction.
  /// @param value The value to send with the L1 transaction.
  /// @param msgNonce The nonce of the transaction.
  /// @param data The data to send with the L1 transaction.
  function fulfillCoreL1Call(address _l2Sender, address to, uint256 value, uint256 msgNonce, bytes calldata data) external {
    bytes32 l1CallHash = _computeL1CallHash(_l2Sender, to, value, msgNonce, data);
    if (_l1CallStatus[l1CallHash] == L1CallStatus.Fulfilled) revert AdditionalZkLighter_L1CallAlreadyFulfilled();
    if (_l1CallStatus[l1CallHash] != L1CallStatus.Ready) revert AdditionalZkLighter_L1CallHashNotReady();
    _fulfillL1Call(l1CallHash, _l2Sender, to, value, data);
  }

  /// @notice Fulfills an EVM-originated L1 call proven against an executed batch.
  ///
  /// @param batchNumber The executed batch whose root commits to this call.
  /// @param proof Sibling nodes ordered from the leaf towards the root.
  /// @param isLeft The zero-based leaf index; bit `i` is set when the sibling at level
  /// `i` is the left child.
  /// @param _l2Sender The initiator of the transaction on the EVM side.
  /// @param to The target of the L1 transaction.
  /// @param value The value to send with the L1 transaction.
  /// @param msgNonce The nonce of the transaction, tracked by the `EvmToL1Messenger`.
  /// @param data The data to send with the L1 transaction.
  function fulfillEvmL1Call(
    uint64 batchNumber,
    bytes32[] calldata proof,
    uint256 isLeft,
    address _l2Sender,
    address to,
    uint256 value,
    uint256 msgNonce,
    bytes calldata data
  ) external {
    if (batchNumber > executedBatchesCount) revert AdditionalZkLighter_BatchNotExecuted();

    bytes32 root = _evmL1CallsRoots[batchNumber];
    if (root == bytes32(0)) revert AdditionalZkLighter_NoEvmL1CallsRoot();

    bytes32 l1CallHash = _computeL1CallHash(_l2Sender, to, value, msgNonce, data);
    _verifyMerkleProof(proof, root, l1CallHash, isLeft);

    if (_l1CallStatus[l1CallHash] == L1CallStatus.Fulfilled) revert AdditionalZkLighter_L1CallAlreadyFulfilled();
    if (_l1CallStatus[l1CallHash] != L1CallStatus.Nonexistent) revert AdditionalZkLighter_L1CallHashAlreadyExists();
    _fulfillL1Call(l1CallHash, _l2Sender, to, value, data);
  }

  function _verifyMerkleProof(bytes32[] calldata proof, bytes32 root, bytes32 leaf, uint256 isLeft) internal pure {
    bytes32 currentNode = leaf;
    assembly {
      let offset := proof.offset
      let length := proof.length

      for {
        let i := 0
      } iszero(eq(i, length)) {
        i := add(i, 1)
      } {
        let isLeftBit := and(shr(i, isLeft), 1)

        switch isLeftBit
        case 0 {
          mstore(0x00, currentNode)
          mstore(0x20, calldataload(offset))
        }
        case 1 {
          mstore(0x00, calldataload(offset))
          mstore(0x20, currentNode)
        }

        offset := add(offset, 0x20)
        currentNode := keccak256(0x00, 0x40)
      }
    }

    if (root != currentNode) revert AdditionalZkLighter_InvalidEvmL1CallProof();
  }

  function _fulfillL1Call(bytes32 l1CallHash, address _l2Sender, address to, uint256 value, bytes calldata data) internal {
    if (l2Sender() != address(0)) revert AdditionalZkLighter_L2SenderNotZero(); // Prevents reentrancy
    if (to == address(this)) revert AdditionalZkLighter_CannotExecuteToSelf();

    _l1CallStatus[l1CallHash] = L1CallStatus.Fulfilled;

    assembly {
      tstore(L2_SENDER_TOFFSET, _l2Sender)
    }

    (bool success, ) = to.call{value: value}(data);
    if (!success) revert AdditionalZkLighter_L1CallFailed();

    assembly {
      tstore(L2_SENDER_TOFFSET, 0)
    }
  }

  function setGasParams(uint32 _maxGasLimit, uint112 _baseFeeOverhead, uint112 _baseFeeScalar) public {
    governance.requireGovernor(msg.sender);
    if (_maxGasLimit > MAX_EVM_TX_GAS_LIMIT) revert AdditionalZkLighter_GasLimitTooHigh();

    maxGasLimit = _maxGasLimit;
    baseFeeOverhead = _baseFeeOverhead;
    baseFeeScalar = _baseFeeScalar;
  }

  function setBlobGasParams(uint112 _blobBaseFeeOverhead, uint112 _blobBaseFeeScalar) public {
    governance.requireGovernor(msg.sender);

    blobBaseFeeOverhead = _blobBaseFeeOverhead;
    blobBaseFeeScalar = _blobBaseFeeScalar;
  }

  function computePriorityFee(uint256 gasLimit) public view returns (uint256) {
    return
      _computePriorityFee({
        gasLimit: gasLimit,
        priorityBaseFee: _computePriorityBaseFee({baseFee: block.basefee, overhead: baseFeeOverhead, scalar: baseFeeScalar}),
        priorityBlobByteFee: _computePriorityBlobByteFee({blobBaseFee: block.blobbasefee, overhead: blobBaseFeeOverhead, scalar: blobBaseFeeScalar})
      });
  }

  /// @notice Returns the Core or EVM sender during `fulfillCoreL1Call` or
  /// `fulfillEvmL1Call`, or `address(0)` when no L1 call is being fulfilled.
  function l2Sender() public view returns (address _l2Sender) {
    /// @solidity memory-safe-assembly
    assembly {
      _l2Sender := tload(L2_SENDER_TOFFSET)
    }
  }

  function _validateGasLimit(uint256 gasLimit, uint256 dataLength, bool isCreation) internal view {
    if (gasLimit > maxGasLimit) revert AdditionalZkLighter_GasLimitTooHigh();
    uint256 intrinsicGas = INTRINSIC_GAS_TX + dataLength * GAS_PER_BYTE;
    if (isCreation) intrinsicGas += INTRINSIC_GAS_CONTRACT_CREATION;
    if (gasLimit < intrinsicGas) revert AdditionalZkLighter_GasLimitTooLow();
  }

  /// @notice Applies the L1 to L2 alias to the given sender address.
  ///
  /// @param sender The sender address to apply the L1 to L2 alias to.
  /// @return l2Address The L2 address of the sender.
  function _applyL1ToL2Alias(address sender) internal pure returns (address l2Address) {
    /// @solidity memory-safe-assembly
    unchecked {
      l2Address = address(uint160(sender) + OFFSET);
    }
  }

  /// @notice Returns the next EVM priority request ID.
  function _nextEvmPriorityRequestId() internal view returns (uint64) {
    return executedEvmPriorityRequestCount + openEvmPriorityRequestCount;
  }
}
