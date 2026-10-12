// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import {ZkLighterFixture} from "./helpers/ZkLighterFixture.sol";
import {AdditionalZkLighter} from "../contracts/AdditionalZkLighter.sol";
import {IGovernance} from "../contracts/interfaces/IGovernance.sol";
import {TxTypes} from "../contracts/lib/TxTypes.sol";

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
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.withdraw(accountIndex, 3, TxTypes.RouteType.Perps, 0);

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.withdraw(accountIndex, 3, TxTypes.RouteType.Perps, uint64(2 ** 60));

    (bool success, bytes memory revertData) = address(zklighter).call(
      abi.encodeWithSignature("withdraw(uint48,uint16,uint8,uint64)", accountIndex, 3, 2, 10)
    );
    assertFalse(success);
    assertEq(revertData.length, 0);
    vm.stopPrank();

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_AccountIsNotRegistered.selector);
    zklighter.withdraw(accountIndex + 5, 3, TxTypes.RouteType.Perps, 10);
  }

  function test_withdrawUSDCSucceeds() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    TxTypes.L1Withdraw memory request = TxTypes.L1Withdraw({
      accountIndex: accountIndex,
      masterAccountIndex: accountIndex,
      assetIndex: 3,
      routeType: TxTypes.RouteType.Perps,
      baseAmount: 100
    });
    uint64 requestId = zklighter.openPriorityRequestCount();
    _expectPriorityEvent(receiver1, requestId, TxTypes.PriorityPubDataTypeL1Withdraw, TxTypes.writeWithdrawPubDataForPriorityQueue(request));

    vm.prank(receiver1);
    zklighter.withdraw(accountIndex, 3, TxTypes.RouteType.Perps, 100);
  }

  function test_withdrawNativeRejectsInvalidInputs() public {
    uint48 accountIndex = _depositNative(sender1, receiver1, 10_000_000);

    vm.startPrank(receiver1);
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.withdraw(accountIndex, 1, TxTypes.RouteType.Perps, 0);

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.withdraw(accountIndex, 1, TxTypes.RouteType.Perps, uint64(2 ** 60));

    (bool success, bytes memory revertData) = address(zklighter).call(
      abi.encodeWithSignature("withdraw(uint48,uint16,uint8,uint64)", accountIndex, 1, 2, 10)
    );
    assertFalse(success);
    assertEq(revertData.length, 0);
    vm.stopPrank();

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_AccountIsNotRegistered.selector);
    zklighter.withdraw(accountIndex + 5, 1, TxTypes.RouteType.Perps, 10);
  }

  function test_withdrawNativeSucceeds() public {
    uint48 accountIndex = _depositNative(sender1, receiver1, 10_000_000);
    TxTypes.L1Withdraw memory request = TxTypes.L1Withdraw({
      accountIndex: accountIndex,
      masterAccountIndex: accountIndex,
      assetIndex: 1,
      routeType: TxTypes.RouteType.Perps,
      baseAmount: 100
    });
    uint64 requestId = zklighter.openPriorityRequestCount();
    _expectPriorityEvent(receiver1, requestId, TxTypes.PriorityPubDataTypeL1Withdraw, TxTypes.writeWithdrawPubDataForPriorityQueue(request));

    vm.prank(receiver1);
    zklighter.withdraw(accountIndex, 1, TxTypes.RouteType.Perps, 100);
  }

  function test_withdrawRejectsUnregisteredAsset() public {
    uint48 accountIndex = _depositNative(sender1, receiver1, 10_000_000);
    vm.prank(receiver1);
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidAssetIndex.selector);
    zklighter.withdraw(accountIndex, 59, TxTypes.RouteType.Perps, 1);
  }

  function test_changePubKeyRejectsInvalidInputs() public {
    vm.startPrank(sender1);
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_AccountIsNotRegistered.selector);
    zklighter.changePubKey(type(uint48).max, 0, _validPubKey());

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.changePubKey(type(uint48).max - 1, 255, _validPubKey());

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.changePubKey(type(uint48).max - 1, 0, new bytes(41));

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.changePubKey(type(uint48).max - 1, 0, new bytes(40));

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.changePubKey(type(uint48).max - 1, 0, _invalidPubKey());

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_AccountIsNotRegistered.selector);
    zklighter.changePubKey(type(uint48).max - 1, 0, _validPubKey());
    vm.stopPrank();
  }

  function test_changePubKeySucceeds() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    _expectChangePubKey(receiver1, accountIndex, accountIndex);
    vm.prank(receiver1);
    zklighter.changePubKey(accountIndex, 0, _validPubKey());
  }

  function test_changePubKeyResolvesNilAccountIndex() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    _expectChangePubKey(receiver1, accountIndex, accountIndex);
    vm.prank(receiver1);
    zklighter.changePubKey(type(uint48).max, 0, _validPubKey());
  }

  function test_setSystemConfigRejectsNonGovernor() public {
    TxTypes.SetSystemConfig memory params = _systemConfig();
    vm.prank(sender1);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    zklighter.setSystemConfig(params);
  }

  function test_setSystemConfigRejectsInvalidFee() public {
    TxTypes.SetSystemConfig memory params = _systemConfig();
    params.maxIntegratorSpotTakerFee = 1_000_005;
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidFeeAmount.selector);
    zklighter.setSystemConfig(params);
  }

  function test_setSystemConfigSucceeds() public {
    TxTypes.SetSystemConfig memory params = _systemConfig();
    bytes memory pubData = TxTypes.writeSetSystemConfigPubDataForPriorityQueue(params);
    _expectPriorityEvent(address(this), 0, TxTypes.PriorityPubDataTypeL1SetSystemConfig, pubData);

    zklighter.setSystemConfig(params);
  }

  function test_cancelAllOrdersRejectsInvalidInputs() public {
    vm.prank(receiver1);
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_AccountIsNotRegistered.selector);
    zklighter.cancelAllOrders(15);

    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    vm.prank(receiver1);
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidAccountIndex.selector);
    zklighter.cancelAllOrders(type(uint48).max);
    assertGt(accountIndex, 0);
  }

  function test_cancelAllOrdersSucceeds() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    TxTypes.CancelAllOrders memory request = TxTypes.CancelAllOrders({accountIndex: accountIndex, masterAccountIndex: accountIndex});
    _expectPriorityEvent(receiver1, 1, TxTypes.PriorityPubDataTypeL1CancelAllOrders, TxTypes.writeCancelAllOrdersPubDataForPriorityQueue(request));

    vm.prank(receiver1);
    zklighter.cancelAllOrders(accountIndex);
  }

  function test_createOrderRejectsInvalidInputs() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    vm.startPrank(receiver1);
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidAccountIndex.selector);
    zklighter.createOrder(type(uint48).max, 1, 1, 1, 1, 1);

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.createOrder(accountIndex, 1, 1, 1, 2, 1);

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.createOrder(accountIndex, 1, 1, 0, 1, 1);

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.createOrder(accountIndex, 1, 1, 1, 1, 2);
    vm.stopPrank();
  }

  function test_createOrderSucceeds() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    TxTypes.CreateOrder memory request = TxTypes.CreateOrder({
      accountIndex: accountIndex,
      masterAccountIndex: accountIndex,
      publicMarketIndex: 1,
      baseAmount: 1,
      price: 1,
      isAsk: 1,
      orderType: 1
    });
    _expectPriorityEvent(receiver1, 1, TxTypes.PriorityPubDataTypeL1CreateOrder, TxTypes.writeCreateOrderPubDataForPriorityQueue(request));

    vm.prank(receiver1);
    zklighter.createOrder(accountIndex, 1, 1, 1, 1, 1);
  }

  function test_burnSharesRejectsInvalidInputs() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    uint48 validPoolIndex = 2 ** 47;
    vm.startPrank(receiver1);
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidAccountIndex.selector);
    zklighter.burnShares(type(uint48).max, validPoolIndex, 1);

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidAccountIndex.selector);
    zklighter.burnShares(accountIndex, 1, 1);

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidAccountIndex.selector);
    zklighter.burnShares(accountIndex, type(uint48).max, 1);

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.burnShares(accountIndex, validPoolIndex, 0);

    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
    zklighter.burnShares(accountIndex, validPoolIndex, 2 ** 60);
    vm.stopPrank();
  }

  function test_burnSharesSucceeds() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    uint48 poolIndex = 2 ** 47;
    TxTypes.BurnShares memory request = TxTypes.BurnShares({
      accountIndex: accountIndex,
      masterAccountIndex: accountIndex,
      publicPoolIndex: poolIndex,
      sharesAmount: 5
    });
    _expectPriorityEvent(receiver1, 1, TxTypes.PriorityPubDataTypeL1BurnShares, TxTypes.writeBurnSharesPubDataForPriorityQueue(request));

    vm.prank(receiver1);
    zklighter.burnShares(accountIndex, poolIndex, 5);
  }

  function test_activateDesertModeAfterExpiration() public {
    uint48 accountIndex = _depositUSDC(sender1, receiver1, 10_000_000);
    vm.prank(receiver1);
    zklighter.createOrder(accountIndex, 1, 1, 1, 1, 1);
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
    zklighter.createOrder(accountIndex, 1, 1, 1, 1, 1);
    assertEq(zklighter.openPriorityRequestCount(), 2);

    vm.warp(block.timestamp + 13 days);
    vm.roll(block.number + 10);
    zklighter.activateDesertMode();

    assertFalse(zklighter.desertMode());
  }

  function _expectChangePubKey(address sender, uint48 accountIndex, uint48 masterAccountIndex) internal {
    TxTypes.ChangePubKey memory request = TxTypes.ChangePubKey({
      accountIndex: accountIndex,
      masterAccountIndex: masterAccountIndex,
      apiKeyIndex: 0,
      pubKey: _validPubKey()
    });
    _expectPriorityEvent(sender, 1, TxTypes.PriorityPubDataTypeL1ChangePubKey, TxTypes.writeChangePubKeyPubDataForPriorityQueue(request));
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
