// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";

import {AdditionalZkLighter} from "../../contracts/AdditionalZkLighter.sol";
import {Governance} from "../../contracts/Governance.sol";
import {Storage} from "../../contracts/Storage.sol";
import {ZkLighterTest} from "../../contracts/test/ZkLighterTest.sol";
import {DesertVerifierTest} from "../../contracts/test/DesertVerifierTest.sol";
import {OwnableERC20} from "../../contracts/test/OwnableERC20.sol";
import {ZkLighterVerifierTest} from "../../contracts/test/ZkLighterVerifierTest.sol";
import {TxTypes} from "../../contracts/lib/TxTypes.sol";
import {Proxy} from "../../contracts/proxy/Proxy.sol";

abstract contract ZkLighterFixture is Test {
  bytes32 internal constant GENESIS_STATE_ROOT = 0x9138b1881fc37551cd6da339fd8b968bae7b3cc36ee78c857c4c0e9b923720dc;
  bytes32 internal constant GENESIS_VALIDIUM_ROOT = 0xa96f8fe3b07701bc823ccaa874bb6c07e71823cf52c67eac12283b2ac142feac;

  event Deposit(uint48 toAccountIndex, address toAddress, uint16 assetIndex, TxTypes.RouteType routeType, uint128 baseAmount);
  event CreateMarket(TxTypes.CreateMarket params, uint8 sizeDecimals, uint8 priceDecimals, bytes32 symbol);
  event UpdateMarket(TxTypes.UpdateMarket params);
  event NewPriorityRequest(address sender, uint64 serialId, uint8 pubdataType, bytes pubData, uint64 expirationTimestamp);
  event DesertMode();

  struct PerpsData {
    uint32 quoteMultiplier;
    uint32 takerFee;
    uint32 makerFee;
    uint32 liquidationFee;
    uint48 minBaseAmount;
    uint48 minQuoteAmount;
    uint16 defaultInitialMarginFraction;
    uint16 minInitialMarginFraction;
    uint16 maintenanceMarginFraction;
    uint16 closeOutMarginFraction;
    uint32 interestRate;
    uint24 fundingClampSmall;
    uint24 fundingClampBig;
    uint56 openInterestLimit;
    uint48 orderQuoteLimit;
  }

  struct SpotData {
    uint16 baseAssetIndex;
    uint16 quoteAssetIndex;
    uint56 sizeExtensionMultiplier;
    uint56 quoteExtensionMultiplier;
    uint32 takerFee;
    uint32 makerFee;
    uint48 minBaseAmount;
    uint48 minQuoteAmount;
    uint48 orderQuoteLimit;
  }

  struct UpdateSpotData {
    uint8 status;
    uint32 takerFee;
    uint32 makerFee;
    uint48 minBaseAmount;
    uint48 minQuoteAmount;
    uint48 orderQuoteLimit;
  }

  OwnableERC20 internal usdc;
  Governance internal governance;
  AdditionalZkLighter internal additionalZkLighter;
  ZkLighterTest internal zklighter;

  address internal sender1 = address(0x1001);
  address internal sender2 = address(0x1002);
  address internal receiver1 = address(0x2001);
  address internal receiver2 = address(0x2002);

  function setUp() public virtual {
    usdc = new OwnableERC20("USD Coin", "USDC", 6);
    Governance governanceImplementation = new Governance();
    Proxy governanceProxy = new Proxy(address(governanceImplementation), abi.encode(address(this), address(usdc)));
    governance = Governance(address(governanceProxy));
    governance.setValidator(address(this), true);

    ZkLighterVerifierTest verifierImplementation = new ZkLighterVerifierTest();
    Proxy verifierProxy = new Proxy(address(verifierImplementation), "");
    ZkLighterVerifierTest verifier = ZkLighterVerifierTest(address(verifierProxy));
    AdditionalZkLighter additional = new AdditionalZkLighter();
    DesertVerifierTest desertVerifier = new DesertVerifierTest();
    ZkLighterTest implementation = new ZkLighterTest();
    Proxy zklighterProxy = new Proxy(
      address(implementation),
      abi.encode(address(governance), address(verifier), address(additional), address(desertVerifier), GENESIS_STATE_ROOT, GENESIS_VALIDIUM_ROOT)
    );
    zklighter = ZkLighterTest(payable(address(zklighterProxy)));
    additionalZkLighter = additional;

    usdc.mint(sender1, type(uint128).max);
    usdc.mint(sender2, type(uint128).max);
    usdc.mint(address(this), type(uint128).max);
    vm.prank(sender1);
    usdc.approve(address(zklighter), type(uint256).max);
    vm.prank(sender2);
    usdc.approve(address(zklighter), type(uint256).max);
    usdc.approve(address(zklighter), type(uint256).max);
    vm.deal(sender1, 100_000 ether);
    vm.deal(sender2, 100_000 ether);
    vm.deal(receiver1, 100_000 ether);
    vm.deal(receiver2, 100_000 ether);
  }

  function _depositUSDC(address sender, address receiver, uint256 amount) internal returns (uint48 accountIndex) {
    accountIndex = zklighter.addressToAccountIndex(receiver);
    if (accountIndex == 0) {
      accountIndex = zklighter.lastAccountIndex() + 1;
    }
    uint64 requestId = zklighter.executedPriorityRequestCount() + zklighter.openPriorityRequestCount();
    uint64 baseAmount = uint64(amount);
    TxTypes.Deposit memory request = TxTypes.Deposit({
      accountIndex: accountIndex,
      toAddress: receiver,
      assetIndex: 3,
      routeType: TxTypes.RouteType.Perps,
      baseAmount: baseAmount
    });
    bytes memory pubData = TxTypes.writeDepositPubDataForPriorityQueue(request);

    _expectPriorityEvent(sender, requestId, TxTypes.PriorityPubDataTypeL1Deposit, pubData);
    vm.expectEmit(false, false, false, true, address(zklighter));
    emit Deposit(accountIndex, receiver, 3, TxTypes.RouteType.Perps, baseAmount);
    vm.prank(sender);
    zklighter.deposit(receiver, 3, TxTypes.RouteType.Perps, amount);

    assertEq(zklighter.addressToAccountIndex(receiver), accountIndex);
  }

  function _depositUSDCToSystemAccount(address sender, address receiver, uint48 accountIndex) internal {
    uint64 requestId = zklighter.executedPriorityRequestCount() + zklighter.openPriorityRequestCount();
    TxTypes.Deposit memory request = TxTypes.Deposit({
      accountIndex: accountIndex,
      toAddress: address(0),
      assetIndex: 3,
      routeType: TxTypes.RouteType.Perps,
      baseAmount: 10_000_000
    });
    bytes memory pubData = TxTypes.writeDepositPubDataForPriorityQueue(request);

    _expectPriorityEvent(sender, requestId, TxTypes.PriorityPubDataTypeL1Deposit, pubData);
    vm.expectEmit(false, false, false, true, address(zklighter));
    emit Deposit(accountIndex, address(0), 3, TxTypes.RouteType.Perps, 10_000_000);
    vm.prank(sender);
    zklighter.deposit(receiver, 3, TxTypes.RouteType.Perps, 10_000_000);

    assertEq(zklighter.addressToAccountIndex(receiver), 0);
  }

  function _depositNative(address sender, address receiver, uint64 baseAmount) internal returns (uint48 accountIndex) {
    accountIndex = zklighter.addressToAccountIndex(receiver);
    if (accountIndex == 0) {
      accountIndex = zklighter.lastAccountIndex() + 1;
    }
    uint64 requestId = zklighter.executedPriorityRequestCount() + zklighter.openPriorityRequestCount();
    TxTypes.Deposit memory request = TxTypes.Deposit({
      accountIndex: accountIndex,
      toAddress: receiver,
      assetIndex: 1,
      routeType: TxTypes.RouteType.Spot,
      baseAmount: baseAmount
    });
    bytes memory pubData = TxTypes.writeDepositPubDataForPriorityQueue(request);
    uint256 amount = uint256(baseAmount) * 10 ** 10;

    _expectPriorityEvent(sender, requestId, TxTypes.PriorityPubDataTypeL1Deposit, pubData);
    vm.expectEmit(false, false, false, true, address(zklighter));
    emit Deposit(accountIndex, receiver, 1, TxTypes.RouteType.Spot, baseAmount);
    vm.prank(sender);
    zklighter.deposit{value: amount}(receiver, 1, TxTypes.RouteType.Spot, amount);

    assertEq(zklighter.addressToAccountIndex(receiver), accountIndex);
  }

  function _expectPriorityEvent(address sender, uint64 requestId, uint8 requestType, bytes memory pubData) internal {
    vm.expectEmit(false, false, false, true, address(zklighter));
    emit NewPriorityRequest(sender, requestId, requestType, pubData, uint64(block.timestamp + zklighter.PRIORITY_EXPIRATION()));
  }

  function _validPubKey() internal pure returns (bytes memory) {
    return hex"01000000000000000200000000000000030000000000000004000000000000000500000000000000";
  }

  function _invalidPubKey() internal pure returns (bytes memory) {
    return hex"010000000000000002000000000000000300000000000000040000000000000001000000ffffffff";
  }

  function _validPerpsData() internal pure returns (PerpsData memory data) {
    data.quoteMultiplier = 1;
    data.takerFee = 2;
    data.makerFee = 1;
    data.liquidationFee = 1;
    data.minBaseAmount = 1;
    data.minQuoteAmount = 1;
    data.defaultInitialMarginFraction = 1;
    data.minInitialMarginFraction = 1;
    data.maintenanceMarginFraction = 1;
    data.closeOutMarginFraction = 1;
    data.interestRate = 1;
    data.fundingClampSmall = 1;
    data.fundingClampBig = 1;
    data.openInterestLimit = 1;
    data.orderQuoteLimit = 1;
  }

  function _packPerps(PerpsData memory data) internal pure returns (bytes memory) {
    return
      abi.encodePacked(
        data.quoteMultiplier,
        data.takerFee,
        data.makerFee,
        data.liquidationFee,
        data.minBaseAmount,
        data.minQuoteAmount,
        data.defaultInitialMarginFraction,
        data.minInitialMarginFraction,
        data.maintenanceMarginFraction,
        data.closeOutMarginFraction,
        data.interestRate,
        data.fundingClampSmall,
        data.fundingClampBig,
        data.openInterestLimit,
        data.orderQuoteLimit
      );
  }

  function _packUpdatePerps(uint8 status, PerpsData memory data) internal pure returns (bytes memory) {
    return
      abi.encodePacked(
        status,
        data.takerFee,
        data.makerFee,
        data.liquidationFee,
        data.minBaseAmount,
        data.minQuoteAmount,
        data.defaultInitialMarginFraction,
        data.minInitialMarginFraction,
        data.maintenanceMarginFraction,
        data.closeOutMarginFraction,
        data.interestRate,
        data.fundingClampSmall,
        data.fundingClampBig,
        data.openInterestLimit,
        data.orderQuoteLimit
      );
  }

  function _validSpotData() internal pure returns (SpotData memory data) {
    data.baseAssetIndex = 1;
    data.quoteAssetIndex = 3;
    data.sizeExtensionMultiplier = 1_000_000;
    data.quoteExtensionMultiplier = 1_000_000;
    data.takerFee = 2;
    data.makerFee = 1;
    data.minBaseAmount = 1;
    data.minQuoteAmount = 1;
    data.orderQuoteLimit = 1;
  }

  function _packSpot(SpotData memory data) internal pure returns (bytes memory) {
    return
      abi.encodePacked(
        data.baseAssetIndex,
        data.quoteAssetIndex,
        data.sizeExtensionMultiplier,
        data.quoteExtensionMultiplier,
        data.takerFee,
        data.makerFee,
        data.minBaseAmount,
        data.minQuoteAmount,
        data.orderQuoteLimit
      );
  }

  function _packUpdateSpot(UpdateSpotData memory data) internal pure returns (bytes memory) {
    return abi.encodePacked(data.status, data.takerFee, data.makerFee, data.minBaseAmount, data.minQuoteAmount, data.orderQuoteLimit);
  }
}
