// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import {ZkLighterFixture} from "./helpers/ZkLighterFixture.sol";
import {AdditionalZkLighter} from "../contracts/AdditionalZkLighter.sol";
import {IGovernance} from "../contracts/interfaces/IGovernance.sol";
import {L1CoreMessaging} from "../contracts/messaging/L1CoreMessaging.sol";
import {TxTypes} from "../contracts/lib/TxTypes.sol";

/// Token entrypoints (deposit) stay on ZkLighter; every non-token priority request goes through L1CoreMessaging.
contract ZkLighterRequestTests is ZkLighterFixture {
  function test_depositUSDCRejectsInvalidInputs() public {
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidDepositAmount.selector);
    zklighter.deposit(receiver1, 3, TxTypes.RouteType.Perps, 0);

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_AccountIsNotRegistered.selector);
    zklighter.deposit(address(0), 3, TxTypes.RouteType.Perps, 1_000_000_000);

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidDepositAmount.selector);
    zklighter.deposit(receiver1, 3, TxTypes.RouteType.Perps, 2 ** 60);
  }

  function test_depositUSDCSucceeds() public {
    _depositUSDC(sender1, receiver1, 10_000_000);
  }

  function test_depositUSDCRegistersReceiverOnce() public {
    assertEq(zklighter.addressToAccountIndex(receiver1), 0);
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    assertGt(accountIndex, 0);
    assertEq(_depositUSDC(sender2, receiver1, 10_000_000), accountIndex);
  }

  function test_depositUSDCToTreasuryUsesSystemAccount() public {
    zklighter.setTreasury(receiver1);
    _depositUSDCToSystemAccount(sender1, receiver1, 0);
  }

  function test_depositUSDCToInsuranceFundUsesSystemAccount() public {
    zklighter.setInsuranceFundOperator(receiver1);
    _depositUSDCToSystemAccount(sender1, receiver1, 1);
  }

  function test_depositNativeSucceeds() public {
    _depositNative(sender1, receiver1, 1_000_000);
  }

  function test_depositNativeRegistersReceiverOnce() public {
    assertEq(zklighter.addressToAccountIndex(receiver1), 0);
    uint48 accountIndex = _depositNative(sender1, receiver1, 1_000_000);
    assertGt(accountIndex, 0);
    assertEq(_depositNative(sender2, receiver1, 1_000_000), accountIndex);
  }

  function test_withdrawUSDCRejectsInvalidInputs() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);

    vm.startPrank(receiver1);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidWithdrawAmount.selector);
    coreMessaging.withdraw(accountIndex, 3, TxTypes.RouteType.Perps, 0);

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidWithdrawAmount.selector);
    coreMessaging.withdraw(accountIndex, 3, TxTypes.RouteType.Perps, uint64(2 ** 60));

    (bool success, bytes memory revertData) = address(coreMessaging).call(
      abi.encodeWithSignature("withdraw(uint48,uint16,uint8,uint64)", accountIndex, 3, 2, 10)
    );
    assertFalse(success);
    assertEq(revertData.length, 0);
    vm.stopPrank();

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_AccountIsNotRegistered.selector);
    coreMessaging.withdraw(accountIndex + 5, 3, TxTypes.RouteType.Perps, 10);
  }

  function test_withdrawUSDCSucceeds() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    bytes memory pubData = TxTypes.writeWithdrawPubDataForPriorityQueue(accountIndex, accountIndex, 3, TxTypes.RouteType.Perps, 100);
    uint64 requestId = zklighter.openPriorityRequestCount();
    _expectPriorityEvent(receiver1, requestId, TxTypes.PriorityPubDataTypeL1Withdraw, pubData);

    vm.prank(receiver1);
    coreMessaging.withdraw(accountIndex, 3, TxTypes.RouteType.Perps, 100);
  }

  function test_withdrawNativeRejectsInvalidInputs() public {
    uint48 accountIndex = _depositNative(sender1, receiver1, 10_000_000);

    vm.startPrank(receiver1);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidWithdrawAmount.selector);
    coreMessaging.withdraw(accountIndex, 1, TxTypes.RouteType.Perps, 0);

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidWithdrawAmount.selector);
    coreMessaging.withdraw(accountIndex, 1, TxTypes.RouteType.Perps, uint64(2 ** 60));

    (bool success, bytes memory revertData) = address(coreMessaging).call(
      abi.encodeWithSignature("withdraw(uint48,uint16,uint8,uint64)", accountIndex, 1, 2, 10)
    );
    assertFalse(success);
    assertEq(revertData.length, 0);
    vm.stopPrank();

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_AccountIsNotRegistered.selector);
    coreMessaging.withdraw(accountIndex + 5, 1, TxTypes.RouteType.Perps, 10);
  }

  function test_withdrawNativeSucceeds() public {
    uint48 accountIndex = _depositNative(sender1, receiver1, 10_000_000);
    bytes memory pubData = TxTypes.writeWithdrawPubDataForPriorityQueue(accountIndex, accountIndex, 1, TxTypes.RouteType.Perps, 100);
    uint64 requestId = zklighter.openPriorityRequestCount();
    _expectPriorityEvent(receiver1, requestId, TxTypes.PriorityPubDataTypeL1Withdraw, pubData);

    vm.prank(receiver1);
    coreMessaging.withdraw(accountIndex, 1, TxTypes.RouteType.Perps, 100);
  }

  function test_withdrawRejectsUnregisteredAsset() public {
    uint48 accountIndex = _depositNative(sender1, receiver1, 10_000_000);
    vm.prank(receiver1);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidAssetIndex.selector);
    coreMessaging.withdraw(accountIndex, 59, TxTypes.RouteType.Perps, 1);
  }

  function test_changePubKeyRejectsInvalidInputs() public {
    vm.startPrank(sender1);
    // NIL_ACCOUNT_INDEX resolves to the sender's own account, so an unregistered sender is rejected
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_AccountIsNotRegistered.selector);
    coreMessaging.changePubKey(type(uint48).max, 0, _validPubKey());

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidApiKeyIndex.selector);
    coreMessaging.changePubKey(type(uint48).max - 1, 255, _validPubKey());

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidPubKey.selector);
    coreMessaging.changePubKey(type(uint48).max - 1, 0, new bytes(41));

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidPubKey.selector);
    coreMessaging.changePubKey(type(uint48).max - 1, 0, _invalidPubKey());

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_AccountIsNotRegistered.selector);
    coreMessaging.changePubKey(type(uint48).max - 1, 0, _validPubKey());
    vm.stopPrank();
  }

  function test_changePubKeySucceeds() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    _expectChangePubKey(receiver1, accountIndex, accountIndex);
    vm.prank(receiver1);
    coreMessaging.changePubKey(accountIndex, 0, _validPubKey());
  }

  function test_changePubKeyResolvesNilAccountIndex() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    _expectChangePubKey(receiver1, accountIndex, accountIndex);
    vm.prank(receiver1);
    coreMessaging.changePubKey(type(uint48).max, 0, _validPubKey());
  }

  function test_changeECDSAPubKeyRejectsInvalidInputs() public {
    vm.startPrank(sender1);
    // NIL_ACCOUNT_INDEX resolves to the sender's own account, so an unregistered sender is rejected
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_AccountIsNotRegistered.selector);
    coreMessaging.changeECDSAPubKey(type(uint48).max, 0, _validECDSAPubKey());

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidApiKeyIndex.selector);
    coreMessaging.changeECDSAPubKey(type(uint48).max - 1, 255, _validECDSAPubKey());

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidPubKey.selector);
    coreMessaging.changeECDSAPubKey(type(uint48).max - 1, 0, new bytes(33));

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidPubKey.selector);
    coreMessaging.changeECDSAPubKey(type(uint48).max - 1, 0, new bytes(66));

    // Unsupported prefix
    bytes memory pubKey = _validECDSAPubKey();
    pubKey[0] = 0x02;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidPubKey.selector);
    coreMessaging.changeECDSAPubKey(type(uint48).max - 1, 0, pubKey);

    // Zero prefix with non-zero coordinates
    pubKey[0] = 0x00;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidPubKey.selector);
    coreMessaging.changeECDSAPubKey(type(uint48).max - 1, 0, pubKey);

    // Point not on the curve
    pubKey = _validECDSAPubKey();
    pubKey[64] = bytes1(uint8(pubKey[64]) ^ 1);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidPubKey.selector);
    coreMessaging.changeECDSAPubKey(type(uint48).max - 1, 0, pubKey);

    // Coordinates outside the field
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidPubKey.selector);
    coreMessaging.changeECDSAPubKey(type(uint48).max - 1, 0, abi.encodePacked(bytes1(0x04), type(uint256).max, type(uint256).max));

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_AccountIsNotRegistered.selector);
    coreMessaging.changeECDSAPubKey(type(uint48).max - 1, 0, _validECDSAPubKey());
    vm.stopPrank();
  }

  function test_changeECDSAPubKeySucceeds() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    _expectChangeECDSAPubKey(receiver1, accountIndex, accountIndex);
    vm.prank(receiver1);
    coreMessaging.changeECDSAPubKey(accountIndex, 0, _validECDSAPubKey());
  }

  function test_changeECDSAPubKeyResolvesNilAccountIndex() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    _expectChangeECDSAPubKey(receiver1, accountIndex, accountIndex);
    vm.prank(receiver1);
    coreMessaging.changeECDSAPubKey(type(uint48).max, 0, _validECDSAPubKey());
  }

  function test_changeECDSAPubKeyRevokesWithAllZeros() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    bytes memory pubData = TxTypes.writeChangeECDSAPubKeyPubDataForPriorityQueue(
      accountIndex,
      accountIndex,
      0,
      abi.encodePacked(bytes1(0x02), bytes32(0))
    );
    _expectPriorityEvent(receiver1, 1, TxTypes.PriorityPubDataTypeL1ChangeECDSAPubKey, pubData);
    vm.prank(receiver1);
    coreMessaging.changeECDSAPubKey(accountIndex, 0, new bytes(65));
  }

  function test_setSystemConfigRejectsNonGovernor() public {
    TxTypes.SetSystemConfig memory params = _systemConfig();
    vm.prank(sender1);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    coreMessaging.setSystemConfig(params);
  }

  function test_setSystemConfigRejectsInvalidFee() public {
    TxTypes.SetSystemConfig memory params = _systemConfig();
    params.maxIntegratorSpotTakerFee = 1_000_005;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidFeeAmount.selector);
    coreMessaging.setSystemConfig(params);
  }

  function test_setSystemConfigSucceeds() public {
    TxTypes.SetSystemConfig memory params = _systemConfig();
    bytes memory pubData = TxTypes.writeSetSystemConfigPubDataForPriorityQueue(
      params.liquidityPoolIndex,
      params.stakingPoolIndex,
      params.liquidityPoolCooldownPeriod,
      params.stakingPoolLockupPeriod,
      params.maxIntegratorPerpsTakerFee,
      params.maxIntegratorPerpsMakerFee,
      params.maxIntegratorSpotTakerFee,
      params.maxIntegratorSpotMakerFee
    );
    _expectPriorityEvent(address(this), 0, TxTypes.PriorityPubDataTypeL1SetSystemConfig, pubData);
    vm.expectEmit(false, false, false, true, address(coreMessaging));
    emit SetSystemConfig(params);

    coreMessaging.setSystemConfig(params);
  }

  function test_cancelAllOrdersRejectsInvalidInputs() public {
    vm.prank(receiver1);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_AccountIsNotRegistered.selector);
    coreMessaging.cancelAllOrders(15);

    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    vm.prank(receiver1);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidAccountIndex.selector);
    coreMessaging.cancelAllOrders(type(uint48).max);
    assertGt(accountIndex, 0);
  }

  function test_cancelAllOrdersSucceeds() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    bytes memory pubData = TxTypes.writeCancelAllOrdersPubDataForPriorityQueue(accountIndex, accountIndex);
    _expectPriorityEvent(receiver1, 1, TxTypes.PriorityPubDataTypeL1CancelAllOrders, pubData);

    vm.prank(receiver1);
    coreMessaging.cancelAllOrders(accountIndex);
  }

  function test_createOrderRejectsInvalidInputs() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    vm.startPrank(receiver1);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidAccountIndex.selector);
    coreMessaging.createOrder(type(uint48).max, 1, 1, 1, 1, 1);

    // invalid isAsk
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidCreateOrderParameters.selector);
    coreMessaging.createOrder(accountIndex, 1, 1, 1, 2, 1);

    // invalid price
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidCreateOrderParameters.selector);
    coreMessaging.createOrder(accountIndex, 1, 1, 0, 1, 1);

    // invalid orderType
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidCreateOrderParameters.selector);
    coreMessaging.createOrder(accountIndex, 1, 1, 1, 1, 2);

    // NIL_PUBLIC_MARKET_INDEX
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketIndex.selector);
    coreMessaging.createOrder(accountIndex, 255, 1, 1, 1, 1);
    // MAX_PUBLIC_MARKET_INDEX + 1
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketIndex.selector);
    coreMessaging.createOrder(accountIndex, 2 ** 48, 1, 1, 1, 1);
    vm.stopPrank();
  }

  function test_createOrderSucceeds() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    bytes memory pubData = TxTypes.writeCreateOrderPubDataForPriorityQueue(accountIndex, accountIndex, 1, 1, 1, 1, 1);
    _expectPriorityEvent(receiver1, 1, TxTypes.PriorityPubDataTypeL1CreateOrder, pubData);
    vm.expectEmit(false, false, false, true, address(coreMessaging));
    emit CreateOrder(accountIndex, accountIndex, 1, 1, 1, 1, 1);

    vm.prank(receiver1);
    coreMessaging.createOrder(accountIndex, 1, 1, 1, 1, 1);
  }

  function test_createOrderAcceptsMaxPublicMarketIndex() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    bytes memory pubData = TxTypes.writeCreateOrderPubDataForPriorityQueue(accountIndex, accountIndex, 2 ** 48 - 1, 1, 1, 1, 1);
    _expectPriorityEvent(receiver1, 1, TxTypes.PriorityPubDataTypeL1CreateOrder, pubData);

    vm.prank(receiver1);
    coreMessaging.createOrder(accountIndex, 2 ** 48 - 1, 1, 1, 1, 1);
  }

  function test_burnSharesRejectsInvalidInputs() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    uint48 validPoolIndex = 2 ** 47;
    vm.startPrank(receiver1);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidAccountIndex.selector);
    coreMessaging.burnShares(type(uint48).max, validPoolIndex, 1);

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidAccountIndex.selector);
    coreMessaging.burnShares(accountIndex, 1, 1);

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidAccountIndex.selector);
    coreMessaging.burnShares(accountIndex, type(uint48).max, 1);

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidShareAmount.selector);
    coreMessaging.burnShares(accountIndex, validPoolIndex, 0);

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidShareAmount.selector);
    coreMessaging.burnShares(accountIndex, validPoolIndex, 2 ** 60);
    vm.stopPrank();
  }

  function test_burnSharesSucceeds() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    uint48 poolIndex = 2 ** 47;
    bytes memory pubData = TxTypes.writeBurnSharesPubDataForPriorityQueue(accountIndex, accountIndex, poolIndex, 5);
    _expectPriorityEvent(receiver1, 1, TxTypes.PriorityPubDataTypeL1BurnShares, pubData);

    vm.prank(receiver1);
    coreMessaging.burnShares(accountIndex, poolIndex, 5);
  }

  function test_activateDesertModeAfterExpiration() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    vm.prank(receiver1);
    coreMessaging.createOrder(accountIndex, 1, 1, 1, 1, 1);
    assertEq(zklighter.openPriorityRequestCount(), 2);

    vm.warp(block.timestamp + 15 days);
    vm.roll(block.number + 10);
    vm.expectEmit(false, false, false, true, address(zklighter));
    emit DesertMode();
    zklighter.activateDesertMode();

    assertTrue(zklighter.desertMode());
  }

  function test_activateDesertModeDoesNothingWithoutRequests() public {
    assertEq(zklighter.openPriorityRequestCount(), 0);
    zklighter.activateDesertMode();
    assertFalse(zklighter.desertMode());
  }

  function test_activateDesertModeDoesNothingBeforeExpiration() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    vm.prank(receiver1);
    coreMessaging.createOrder(accountIndex, 1, 1, 1, 1, 1);
    assertEq(zklighter.openPriorityRequestCount(), 2);

    vm.warp(block.timestamp + 13 days);
    vm.roll(block.number + 10);
    zklighter.activateDesertMode();

    assertFalse(zklighter.desertMode());
  }

  function _expectChangePubKey(address sender, uint48 accountIndex, uint48 masterAccountIndex) internal {
    bytes memory pubData = TxTypes.writeChangePubKeyPubDataForPriorityQueue(accountIndex, masterAccountIndex, 0, _validPubKey());
    _expectPriorityEvent(sender, 1, TxTypes.PriorityPubDataTypeL1ChangePubKey, pubData);
  }

  function _expectChangeECDSAPubKey(address sender, uint48 accountIndex, uint48 masterAccountIndex) internal {
    bytes memory pubData = TxTypes.writeChangeECDSAPubKeyPubDataForPriorityQueue(accountIndex, masterAccountIndex, 0, _validCompressedECDSAPubKey());
    _expectPriorityEvent(sender, 1, TxTypes.PriorityPubDataTypeL1ChangeECDSAPubKey, pubData);
  }

  function _systemConfig() internal pure returns (TxTypes.SetSystemConfig memory params) {
    params = TxTypes.SetSystemConfig({
      liquidityPoolIndex: 0,
      stakingPoolIndex: 1,
      liquidityPoolCooldownPeriod: 1_000,
      stakingPoolLockupPeriod: 2_000,
      maxIntegratorPerpsTakerFee: 10,
      maxIntegratorPerpsMakerFee: 10,
      maxIntegratorSpotTakerFee: 1_000,
      maxIntegratorSpotMakerFee: 20
    });
  }
}
