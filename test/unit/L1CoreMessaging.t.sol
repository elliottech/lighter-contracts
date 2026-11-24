// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {L1CoreMessaging} from "../../contracts/messaging/L1CoreMessaging.sol";
import {IZkLighter, IZkLighterPublic} from "../../contracts/interfaces/IZkLighter.sol";
import {Config} from "../../contracts/Config.sol";
import {IGovernance} from "../../contracts/interfaces/IGovernance.sol";
import {IZkLighterDesertMode} from "../../contracts/interfaces/IZkLighterDesertMode.sol";
import {Proxy} from "../../contracts/proxy/Proxy.sol";
import {TxTypes} from "../../contracts/lib/TxTypes.sol";
import {SimpleERC20} from "../helpers/TestTokens.sol";
import {AdditionalZkLighter} from "../../contracts/AdditionalZkLighter.sol";
import {ZkLighterTest} from "../../contracts/test/ZkLighterTest.sol";
import {GovernanceTest} from "../../contracts/test/GovernanceTest.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                       HELPER CONTRACTS                     */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

contract MockZkLighter {
  address internal constant TREASURY = address(0x100);
  address internal constant INSURANCE = address(0x101);

  function treasury() external pure returns (address) {
    return TREASURY;
  }

  function insuranceFundOperator() external pure returns (address) {
    return INSURANCE;
  }

  function addressToAccountIndex(address) external pure returns (uint48) {
    return 0;
  }

  function addPriorityRequestExt(address, uint8, bytes memory, bytes memory) external {}

  function assetConfigs(uint16 assetIndex) external pure returns (address, uint8, uint56, uint128, uint64, uint64) {
    return (assetIndex == 0 ? address(0) : address(uint160(assetIndex)), 1, 1, 1, type(uint64).max, 1);
  }
}

contract MockGovernance {
  function requireGovernor(address) external pure {}
}

contract CoreMessagingHarness is L1CoreMessaging {
  function setDependencies(IZkLighterPublic _zkLighter, IGovernance _governance) external {
    zkLighter = _zkLighter;
    governance = _governance;
  }

  function validateCreateMarketParams(TxTypes.CreateMarket calldata _params) external view {
    _validateCreateMarketParams(_params);
  }

  function validateUpdateMarketParams(TxTypes.UpdateMarket calldata _params) external pure {
    _validateUpdateMarketParams(_params);
  }

  function bswap64(uint256 x) external pure returns (uint256) {
    return _bswap64(x);
  }

  function readU64LEAt(bytes calldata data, uint256 o) external pure returns (uint64) {
    return _readU64LEAt(data, o);
  }

  function validateAndCompress(bytes1 _prefix, bytes32 _x, bytes32 _y) external pure returns (bytes memory) {
    return _validateAndCompress(_prefix, _x, _y);
  }
}

abstract contract CoreMessagingTestBase is Test, Config {
  CoreMessagingHarness h;

  function setUp() public virtual {
    MockZkLighter mock = new MockZkLighter();
    MockGovernance governance = new MockGovernance();
    h = new CoreMessagingHarness();
    h.setDependencies(IZkLighterPublic(address(mock)), IGovernance(address(governance)));
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                           STRUCTS                          */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  struct CommonPerpsInputs {
    uint32 takerFee;
    uint32 makerFee;
    uint32 liquidationFee;
    uint48 minBaseAmount;
    uint48 minQuoteAmount;
    uint16 defaultIMF;
    uint16 minIMF;
    uint16 maintenanceMF;
    uint16 closeOutMF;
    uint32 interestRate;
    uint24 fundingClampSmall;
    uint24 fundingClampBig;
    uint56 openInterestLimit;
    uint48 orderQuoteLimit;
  }

  struct CommonSpotInputs {
    uint32 takerFee;
    uint32 makerFee;
    uint48 minBaseAmount;
    uint48 minQuoteAmount;
    uint48 orderQuoteLimit;
  }

  struct CreateSpotExtraInputs {
    uint16 baseAssetIndex;
    uint16 quoteAssetIndex;
    uint56 sizeExtMul;
    uint56 quoteExtMul;
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                        CALL HELPERS                        */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function _callCreatePerps(uint16 idx, bytes memory data) internal view {
    h.validateCreateMarketParams(TxTypes.CreateMarket({marketIndex: idx, marketType: TxTypes.MarketType.Perps, marketData: data}));
  }

  function _callCreateSpot(uint16 idx, bytes memory data) internal view {
    h.validateCreateMarketParams(TxTypes.CreateMarket({marketIndex: idx, marketType: TxTypes.MarketType.Spot, marketData: data}));
  }

  function _callUpdatePerps(uint16 idx, bytes memory data) internal view {
    h.validateUpdateMarketParams(TxTypes.UpdateMarket({marketIndex: idx, marketType: TxTypes.MarketType.Perps, marketData: data}));
  }

  function _callUpdateSpot(uint16 idx, bytes memory data) internal view {
    h.validateUpdateMarketParams(TxTypes.UpdateMarket({marketIndex: idx, marketType: TxTypes.MarketType.Spot, marketData: data}));
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                      BOUND / PACK HELPERS                  */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function _boundCommonPerps(CommonPerpsInputs memory p) internal pure returns (CommonPerpsInputs memory) {
    p.takerFee = uint32(bound(p.takerFee, 0, FEE_TICK));
    p.makerFee = uint32(bound(p.makerFee, 0, FEE_TICK));
    p.liquidationFee = uint32(bound(p.liquidationFee, 0, FEE_TICK));
    p.minBaseAmount = uint48(bound(p.minBaseAmount, 1, MAX_ORDER_BASE_AMOUNT));
    p.minQuoteAmount = uint48(bound(p.minQuoteAmount, 1, MAX_ORDER_QUOTE_AMOUNT));
    p.closeOutMF = uint16(bound(p.closeOutMF, 1, MARGIN_TICK));
    p.maintenanceMF = uint16(bound(p.maintenanceMF, p.closeOutMF, MARGIN_TICK));
    p.minIMF = uint16(bound(p.minIMF, p.maintenanceMF, MARGIN_TICK));
    p.defaultIMF = uint16(bound(p.defaultIMF, p.minIMF, MARGIN_TICK));
    p.interestRate = uint32(bound(p.interestRate, 0, FUNDING_RATE_TICK));
    p.fundingClampSmall = uint24(bound(p.fundingClampSmall, 0, FUNDING_RATE_TICK));
    p.fundingClampBig = uint24(bound(p.fundingClampBig, 0, FUNDING_RATE_TICK));
    p.orderQuoteLimit = uint48(bound(p.orderQuoteLimit, p.minQuoteAmount, MAX_ORDER_QUOTE_AMOUNT));
    p.openInterestLimit = uint56(bound(p.openInterestLimit, p.orderQuoteLimit, MAX_MARKET_OPEN_INTEREST));
    return p;
  }

  function _packCommonPerps(CommonPerpsInputs memory p) internal pure returns (bytes memory) {
    return
      bytes.concat(
        abi.encodePacked(
          p.takerFee,
          p.makerFee,
          p.liquidationFee,
          p.minBaseAmount,
          p.minQuoteAmount,
          p.defaultIMF,
          p.minIMF,
          p.maintenanceMF,
          p.closeOutMF
        ),
        abi.encodePacked(p.interestRate, p.fundingClampSmall, p.fundingClampBig, p.openInterestLimit, p.orderQuoteLimit)
      );
  }

  function _boundCommonSpot(CommonSpotInputs memory p) internal pure returns (CommonSpotInputs memory) {
    p.takerFee = uint32(bound(p.takerFee, 0, FEE_TICK));
    p.makerFee = uint32(bound(p.makerFee, 0, FEE_TICK));
    p.minBaseAmount = uint48(bound(p.minBaseAmount, 1, MAX_ORDER_BASE_AMOUNT));
    p.minQuoteAmount = uint48(bound(p.minQuoteAmount, 1, MAX_ORDER_QUOTE_AMOUNT));
    p.orderQuoteLimit = uint48(bound(p.orderQuoteLimit, p.minQuoteAmount, MAX_ORDER_QUOTE_AMOUNT));
    return p;
  }

  function _packCommonSpot(CommonSpotInputs memory p) internal pure returns (bytes memory) {
    return abi.encodePacked(p.takerFee, p.makerFee, p.minBaseAmount, p.minQuoteAmount, p.orderQuoteLimit);
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                       DEFAULT BUILDERS                     */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function _defaultPerps() internal pure returns (CommonPerpsInputs memory p) {
    p.takerFee = 100;
    p.makerFee = 50;
    p.liquidationFee = 200;
    p.minBaseAmount = 1;
    p.minQuoteAmount = 1;
    p.defaultIMF = MARGIN_TICK;
    p.minIMF = 5000;
    p.maintenanceMF = 2500;
    p.closeOutMF = 1000;
    p.interestRate = 500;
    p.fundingClampSmall = 100;
    p.fundingClampBig = 200;
    p.orderQuoteLimit = 1000;
    p.openInterestLimit = 100_000;
  }

  function _defaultSpot() internal pure returns (CommonSpotInputs memory p) {
    p.takerFee = 100;
    p.makerFee = 50;
    p.minBaseAmount = 1;
    p.minQuoteAmount = 1;
    p.orderQuoteLimit = 1;
  }

  /// @dev Returns valid 55-byte common perps data from defaults.
  function _defaultCommonPerpsBytes() internal pure returns (bytes memory) {
    return _packCommonPerps(_boundCommonPerps(_defaultPerps()));
  }

  /// @dev Bounds, packs, and prepends quoteMultiplier=1 to produce valid 59-byte create-perps data.
  function _packCreatePerpsData(CommonPerpsInputs memory p) internal pure returns (bytes memory) {
    return abi.encodePacked(uint32(1), _packCommonPerps(p));
  }
}

abstract contract L1CoreMessagingMockBase is Test {
  L1CoreMessaging internal l1CoreMessaging;

  address internal governor = makeAddr("governor");
  address internal user = makeAddr("user");
  address internal other = makeAddr("other");
  address internal zkLighter = makeAddr("zkLighter");
  address internal governance = makeAddr("governance");

  function setUp() public virtual {
    vm.mockCall(zkLighter, abi.encodeWithSelector(IZkLighterPublic.addressToAccountIndex.selector), abi.encode(uint48(0)));
    vm.mockCall(zkLighter, abi.encodeWithSelector(IZkLighterPublic.treasury.selector), abi.encode(governor));
    vm.mockCall(zkLighter, abi.encodeWithSelector(IZkLighterPublic.insuranceFundOperator.selector), abi.encode(other));
    vm.mockCall(zkLighter, abi.encodeWithSelector(IZkLighter.addPriorityRequestExt.selector), "");
    vm.mockCall(governance, abi.encodeWithSelector(IGovernance.requireGovernor.selector, governor), "");

    L1CoreMessaging impl = new L1CoreMessaging();
    l1CoreMessaging = L1CoreMessaging(address(new Proxy(address(impl), abi.encode(address(zkLighter), address(governance)))));
  }
}

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                  CREATE MARKET TESTS                          */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

contract L1CoreMessaging_CreateMarketTest is CoreMessagingTestBase {
  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                        PACK HELPERS                        */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function _packValidCreatePerpsData(uint32 quoteMultiplier, CommonPerpsInputs memory perps) internal pure returns (bytes memory) {
    quoteMultiplier = uint32(bound(quoteMultiplier, 1, MAX_QUOTE_MULTIPLIER));
    perps = _boundCommonPerps(perps);
    return abi.encodePacked(quoteMultiplier, _packCommonPerps(perps));
  }

  function _packValidCreateSpotData(CreateSpotExtraInputs memory extra, CommonSpotInputs memory spot) internal pure returns (bytes memory) {
    if (extra.baseAssetIndex == 0) extra.baseAssetIndex = 1;
    if (extra.quoteAssetIndex == 0) extra.quoteAssetIndex = 2;
    if (extra.baseAssetIndex == extra.quoteAssetIndex) {
      unchecked {
        extra.quoteAssetIndex = extra.baseAssetIndex + 1;
      }
      if (extra.quoteAssetIndex == 0) extra.quoteAssetIndex = 1;
    }
    extra.sizeExtMul = uint56(bound(extra.sizeExtMul, FEE_TICK, MAX_ASSET_EXTENSION_MULTIPLIER));
    extra.sizeExtMul = uint56((extra.sizeExtMul / FEE_TICK) * FEE_TICK);
    if (extra.sizeExtMul == 0) extra.sizeExtMul = uint56(FEE_TICK);

    extra.quoteExtMul = uint56(bound(extra.quoteExtMul, FEE_TICK, MAX_ASSET_EXTENSION_MULTIPLIER));
    extra.quoteExtMul = uint56((extra.quoteExtMul / FEE_TICK) * FEE_TICK);
    if (extra.quoteExtMul == 0) extra.quoteExtMul = uint56(FEE_TICK);

    spot = _boundCommonSpot(spot);
    return abi.encodePacked(extra.baseAssetIndex, extra.quoteAssetIndex, extra.sizeExtMul, extra.quoteExtMul, _packCommonSpot(spot));
  }

  /// @dev Returns valid 44-byte create-spot data with sensible defaults.
  function _defaultCreateSpotData() internal pure returns (bytes memory) {
    CommonSpotInputs memory spot = _defaultSpot();
    return abi.encodePacked(uint16(1), uint16(2), uint56(FEE_TICK), uint56(FEE_TICK), _packCommonSpot(spot));
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                    HAPPY-PATH FUZZ TESTS                   */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function testFuzz_validateCreateMarketPerps(uint16 marketIndex, uint32 qm, CommonPerpsInputs memory perps) public view {
    marketIndex = uint16(bound(marketIndex, 0, MAX_PERPS_MARKET_INDEX));
    _callCreatePerps(marketIndex, _packValidCreatePerpsData(qm, perps));
  }

  function testFuzz_validateCreateMarketSpot(uint16 marketIndex, CreateSpotExtraInputs memory extra, CommonSpotInputs memory spot) public view {
    marketIndex = uint16(bound(marketIndex, MIN_SPOT_MARKET_INDEX, MAX_SPOT_MARKET_INDEX));
    _callCreateSpot(marketIndex, _packValidCreateSpotData(extra, spot));
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                        REVERT TESTS                        */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function test_revert_invalidLength() public {
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketDataLength.selector);
    _callCreatePerps(0, new bytes(58));

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketDataLength.selector);
    _callCreateSpot(MIN_SPOT_MARKET_INDEX, new bytes(43));
  }

  function test_revert_invalidMarketType() public {
    // Solidity 0.8.x ABI-decodes enums strictly, so an out-of-range value (e.g. 2)
    // reverts at the ABI-decoder level before the function body runs. We verify this
    // by sending raw calldata with marketType = 2.
    bytes memory payload = abi.encodeWithSelector(
      CoreMessagingHarness.validateCreateMarketParams.selector,
      uint16(0),
      uint8(2), // invalid MarketType
      hex""
    );
    (bool success, ) = address(h).call(payload);
    assertFalse(success, "should revert for invalid enum");
  }

  function test_revert_perps_invalidMarketIndex() public {
    CommonPerpsInputs memory p = _defaultPerps();
    p = _boundCommonPerps(p);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketIndex.selector);
    _callCreatePerps(MAX_PERPS_MARKET_INDEX + 1, _packCreatePerpsData(p));
  }

  function test_revert_spot_invalidMarketIndex() public {
    bytes memory data = _defaultCreateSpotData();

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketIndex.selector);
    _callCreateSpot(MIN_SPOT_MARKET_INDEX - 1, data);

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketIndex.selector);
    _callCreateSpot(MAX_SPOT_MARKET_INDEX + 1, data);
  }

  function test_revert_perps_invalidQuoteMultiplier() public {
    bytes memory commonPerps = _defaultCommonPerpsBytes();

    // quoteMultiplier == 0
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidQuoteMultiplier.selector);
    _callCreatePerps(0, abi.encodePacked(uint32(0), commonPerps));

    // quoteMultiplier > MAX_QUOTE_MULTIPLIER
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidQuoteMultiplier.selector);
    _callCreatePerps(0, abi.encodePacked(uint32(MAX_QUOTE_MULTIPLIER + 1), commonPerps));
  }

  function test_revert_perps_invalidFee() public {
    CommonPerpsInputs memory p = _boundCommonPerps(_defaultPerps());
    p.takerFee = FEE_TICK + 1;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidFeeAmount.selector);
    _callCreatePerps(0, _packCreatePerpsData(p));
  }

  function test_revert_perps_invalidMarginFraction() public {
    CommonPerpsInputs memory p = _boundCommonPerps(_defaultPerps());
    p.closeOutMF = p.maintenanceMF + 1;
    if (p.closeOutMF > MARGIN_TICK) {
      p.closeOutMF = MARGIN_TICK;
      p.maintenanceMF = MARGIN_TICK - 1;
    }
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarginFraction.selector);
    _callCreatePerps(0, _packCreatePerpsData(p));
  }

  function test_revert_perps_invalidMinAmounts() public {
    CommonPerpsInputs memory p = _boundCommonPerps(_defaultPerps());
    p.minBaseAmount = 0;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMinAmounts.selector);
    _callCreatePerps(0, _packCreatePerpsData(p));
  }

  function test_revert_perps_invalidInterestRate() public {
    CommonPerpsInputs memory p = _boundCommonPerps(_defaultPerps());
    p.interestRate = FUNDING_RATE_TICK + 1;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidFundingClampsOrInterestRate.selector);
    _callCreatePerps(0, _packCreatePerpsData(p));
  }

  function test_revert_perps_invalidFundingClamps() public {
    CommonPerpsInputs memory p = _boundCommonPerps(_defaultPerps());
    p.fundingClampBig = uint24(FUNDING_RATE_TICK) + 1;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidFundingClampsOrInterestRate.selector);
    _callCreatePerps(0, _packCreatePerpsData(p));
  }

  function test_revert_perps_invalidOpenInterestLimit() public {
    CommonPerpsInputs memory p = _boundCommonPerps(_defaultPerps());
    p.orderQuoteLimit = 100;
    p.minQuoteAmount = 1;
    p.openInterestLimit = uint56(p.orderQuoteLimit - 1);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketLimits.selector);
    _callCreatePerps(0, _packCreatePerpsData(p));
  }

  function test_revert_perps_invalidOrderQuoteLimit() public {
    CommonPerpsInputs memory p = _boundCommonPerps(_defaultPerps());
    p.minQuoteAmount = 100;
    p.orderQuoteLimit = 99;
    p.openInterestLimit = uint56(MAX_MARKET_OPEN_INTEREST);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketLimits.selector);
    _callCreatePerps(0, _packCreatePerpsData(p));
  }

  function test_revert_spot_invalidFee() public {
    CommonSpotInputs memory spot = _defaultSpot();
    spot.takerFee = FEE_TICK + 1;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidFeeAmount.selector);
    _callCreateSpot(MIN_SPOT_MARKET_INDEX, abi.encodePacked(uint16(1), uint16(2), uint56(FEE_TICK), uint56(FEE_TICK), _packCommonSpot(spot)));
  }

  function test_revert_spot_invalidMinAmounts() public {
    CommonSpotInputs memory spot = _defaultSpot();
    spot.minBaseAmount = 0;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMinAmounts.selector);
    _callCreateSpot(MIN_SPOT_MARKET_INDEX, abi.encodePacked(uint16(1), uint16(2), uint56(FEE_TICK), uint56(FEE_TICK), _packCommonSpot(spot)));
  }

  function test_revert_spot_invalidMarketLimits() public {
    CommonSpotInputs memory spot = _defaultSpot();
    spot.minQuoteAmount = 100;
    spot.orderQuoteLimit = 99;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketLimits.selector);
    _callCreateSpot(MIN_SPOT_MARKET_INDEX, abi.encodePacked(uint16(1), uint16(2), uint56(FEE_TICK), uint56(FEE_TICK), _packCommonSpot(spot)));
  }

  function test_revert_spot_invalidAssets() public {
    CommonSpotInputs memory spot = _defaultSpot();
    bytes memory data = abi.encodePacked(uint16(5), uint16(5), uint56(FEE_TICK), uint56(FEE_TICK), _packCommonSpot(spot));
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketAssets.selector);
    _callCreateSpot(MIN_SPOT_MARKET_INDEX, data);
  }

  function test_revert_spot_invalidExtMul() public {
    CommonSpotInputs memory spot = _defaultSpot();

    // sizeExtMul == 0
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidExtensionMultiplier.selector);
    _callCreateSpot(MIN_SPOT_MARKET_INDEX, abi.encodePacked(uint16(1), uint16(2), uint56(0), uint56(FEE_TICK), _packCommonSpot(spot)));

    // quoteExtMul not divisible by FEE_TICK
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidExtensionMultiplier.selector);
    _callCreateSpot(MIN_SPOT_MARKET_INDEX, abi.encodePacked(uint16(1), uint16(2), uint56(FEE_TICK), uint56(FEE_TICK + 1), _packCommonSpot(spot)));
  }
}

contract L1CoreMessaging_UpdateMarketTest is CoreMessagingTestBase {
  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                        PACK HELPERS                        */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function _packValidUpdatePerpsData(uint8 status, CommonPerpsInputs memory perps) internal pure returns (bytes memory) {
    status = uint8(bound(status, 0, 1));
    perps = _boundCommonPerps(perps);
    return abi.encodePacked(status, _packCommonPerps(perps));
  }

  function _packValidUpdateSpotData(uint8 status, CommonSpotInputs memory spot) internal pure returns (bytes memory) {
    status = uint8(bound(status, 0, 1));
    spot = _boundCommonSpot(spot);
    return abi.encodePacked(status, _packCommonSpot(spot));
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                    HAPPY-PATH FUZZ TESTS                   */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function testFuzz_validateUpdateMarketPerps(uint16 marketIndex, uint8 status, CommonPerpsInputs memory perps) public view {
    marketIndex = uint16(bound(marketIndex, 0, MAX_PERPS_MARKET_INDEX));
    _callUpdatePerps(marketIndex, _packValidUpdatePerpsData(status, perps));
  }

  function testFuzz_validateUpdateMarketSpot(uint16 marketIndex, uint8 status, CommonSpotInputs memory spot) public view {
    marketIndex = uint16(bound(marketIndex, MIN_SPOT_MARKET_INDEX, MAX_SPOT_MARKET_INDEX));
    _callUpdateSpot(marketIndex, _packValidUpdateSpotData(status, spot));
  }

  /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
  /*                        REVERT TESTS                        */
  /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

  function test_revert_perps_invalidMarketIndex() public {
    CommonPerpsInputs memory p = _boundCommonPerps(_defaultPerps());
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketIndex.selector);
    _callUpdatePerps(MAX_PERPS_MARKET_INDEX + 1, _packValidUpdatePerpsData(0, p));
  }

  function test_revert_spot_invalidMarketIndex() public {
    CommonSpotInputs memory spot = _defaultSpot();
    bytes memory data = _packValidUpdateSpotData(0, spot);

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketIndex.selector);
    _callUpdateSpot(MIN_SPOT_MARKET_INDEX - 1, data);

    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketIndex.selector);
    _callUpdateSpot(MAX_SPOT_MARKET_INDEX + 1, data);
  }

  function test_revert_invalidMarketType() public {
    bytes memory payload = abi.encodeWithSelector(
      CoreMessagingHarness.validateUpdateMarketParams.selector,
      uint16(0),
      uint8(2), // invalid MarketType
      hex""
    );
    (bool success, ) = address(h).call(payload);
    assertFalse(success, "should revert for invalid enum");
  }

  function test_revert_perps_invalidStatus() public {
    CommonPerpsInputs memory p = _boundCommonPerps(_defaultPerps());
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketStatus.selector);
    _callUpdatePerps(0, abi.encodePacked(uint8(2), _packCommonPerps(p)));
  }

  function test_revert_spot_invalidStatus() public {
    CommonSpotInputs memory spot = _defaultSpot();
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketStatus.selector);
    _callUpdateSpot(MIN_SPOT_MARKET_INDEX, abi.encodePacked(uint8(2), _packCommonSpot(spot)));
  }

  function test_revert_spot_invalidFee() public {
    CommonSpotInputs memory spot = _defaultSpot();
    spot.takerFee = FEE_TICK + 1;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidFeeAmount.selector);
    _callUpdateSpot(MIN_SPOT_MARKET_INDEX, abi.encodePacked(uint8(0), _packCommonSpot(spot)));
  }

  function test_revert_spot_invalidMinAmounts() public {
    CommonSpotInputs memory spot = _defaultSpot();
    spot.minBaseAmount = 0;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMinAmounts.selector);
    _callUpdateSpot(MIN_SPOT_MARKET_INDEX, abi.encodePacked(uint8(0), _packCommonSpot(spot)));
  }

  function test_revert_spot_invalidMarketLimits() public {
    CommonSpotInputs memory spot = _defaultSpot();
    spot.minQuoteAmount = 100;
    spot.orderQuoteLimit = 99;
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketLimits.selector);
    _callUpdateSpot(MIN_SPOT_MARKET_INDEX, abi.encodePacked(uint8(0), _packCommonSpot(spot)));
  }

  function test_revert_perps_invalidLength() public {
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketDataLength.selector);
    _callUpdatePerps(0, new bytes(55));
  }

  function test_revert_spot_invalidLength() public {
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarketDataLength.selector);
    _callUpdateSpot(MIN_SPOT_MARKET_INDEX, new bytes(26));
  }
}

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                    CHANGE PUB KEY TESTS                    */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

contract L1CoreMessaging_ChangePubKeyTest is L1CoreMessagingMockBase {
  function test_changePubKey_succeedsForRegisteredUser() public {
    vm.mockCall(zkLighter, abi.encodeWithSelector(IZkLighterPublic.addressToAccountIndex.selector, user), abi.encode(uint48(7)));

    bytes memory pubKey = hex"01000000000000000200000000000000030000000000000004000000000000000500000000000000";

    vm.prank(user);
    l1CoreMessaging.changePubKey(7, 0, pubKey);
  }

  function test_changeECDSAPubKey_succeedsForRegisteredUser() public {
    vm.mockCall(zkLighter, abi.encodeWithSelector(IZkLighterPublic.addressToAccountIndex.selector, user), abi.encode(uint48(7)));

    bytes
      memory pubKey = hex"0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8";

    vm.prank(user);
    l1CoreMessaging.changeECDSAPubKey(7, 0, pubKey);
  }
}

contract L1CoreMessaging_ChangePubKeyHelperTest is CoreMessagingTestBase {
  function _refBswap64(uint256 x) internal pure returns (uint256 result) {
    for (uint256 i = 0; i < 8; ++i) {
      result = (result << 8) | (x & 0xFF);
      x >>= 8;
    }
  }

  function testFuzz_bswap64(uint64 x) public view {
    assertEq(h.bswap64(x), _refBswap64(x));
  }

  function test_bswap64_identity() public view {
    assertEq(h.bswap64(0), 0);
    assertEq(h.bswap64(0x0102030405060708), 0x0807060504030201);
  }

  /// @dev A field element whose big-endian representation looks valid
  /// (< GOLDILOCKS_MODULUS) but whose little-endian value is >= GOLDILOCKS_MODULUS.
  /// BE bytes: 0x02 0x00 0x00 0x00 0xff 0xff 0xff 0xff
  ///   -> BE uint64 = 0x02000000ffffffff (valid, < modulus)
  ///   -> LE uint64 = 0xffffffff00000002 (invalid, >= modulus)
  function test_fieldElement_passesInBE_failsInLE() public view {
    uint64 leValue = 0xffffffff00000002; // >= GOLDILOCKS_MODULUS
    uint64 beValue = uint64(_refBswap64(leValue)); // < GOLDILOCKS_MODULUS
    assertTrue(beValue < GOLDILOCKS_MODULUS, "BE value should be valid");
    assertTrue(leValue >= GOLDILOCKS_MODULUS, "LE value should be invalid");

    // Build a 40-byte key with this element at offset 0
    // Write leValue in LE encoding (raw bytes) at offset 0
    bytes memory key = new bytes(40);
    for (uint256 i = 0; i < 8; ++i) {
      key[i] = bytes1(uint8(leValue >> (i * 8)));
    }

    // readU64LEAt correctly interprets LE -> gets leValue back (>= modulus)
    assertEq(h.readU64LEAt(key, 0), leValue);
  }

  function testFuzz_readU64LEAt(bytes32 seed, uint256 o) public view {
    o = bound(o, 0, 24); // 32 - 8
    bytes memory data = abi.encodePacked(seed);
    uint64 actual = h.readU64LEAt(data, o);
    // Reference: read 8 BE bytes, then byte-swap
    uint64 beWord = uint64(bytes8(seed << (o * 8)));
    uint64 expected = uint64(_refBswap64(beWord));
    assertEq(actual, expected);
  }
}

contract L1CoreMessaging_ValidateAndCompressTest is CoreMessagingTestBase {
  uint256 internal constant SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

  // secp256k1 generator
  uint256 internal constant GX = 0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798;
  uint256 internal constant GY = 0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8;

  // Curve points with a coordinate small enough that `coordinate + SECP256K1_P` still fits in 256 bits
  uint256 internal constant SMALL_X = 1;
  uint256 internal constant SMALL_X_Y = 0x4218f20ae6c646b363db68605822fb14264ca8d2587fdd6fbc750d587e76a7ee;
  uint256 internal constant SMALL_Y_X = 0x1fe1e5ef3fceb5c135ab7741333ce5a6e80d68167653f6b2b24bcbcfaaaff507;
  uint256 internal constant SMALL_Y = 1;

  function _compress(bytes1 prefix, uint256 x, uint256 y) internal view returns (bytes memory) {
    return h.validateAndCompress(prefix, bytes32(x), bytes32(y));
  }

  function _expectInvalid(bytes1 prefix, uint256 x, uint256 y) internal {
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidPubKey.selector);
    h.validateAndCompress(prefix, bytes32(x), bytes32(y));
  }

  function _isOnCurve(uint256 x, uint256 y) internal pure returns (bool) {
    return mulmod(y, y, SECP256K1_P) == addmod(mulmod(mulmod(x, x, SECP256K1_P), x, SECP256K1_P), 7, SECP256K1_P);
  }

  function test_compressesEvenY() public view {
    assertEq(GY & 1, 0);
    assertEq(_compress(0x04, GX, GY), abi.encodePacked(bytes1(0x02), GX));
  }

  function test_compressesOddY() public view {
    uint256 negGY = SECP256K1_P - GY;
    assertEq(negGY & 1, 1);
    assertEq(_compress(0x04, GX, negGY), abi.encodePacked(bytes1(0x03), GX));
  }

  function test_compressesKnownPoints() public view {
    // 2G
    assertEq(
      _compress(
        0x04,
        0xc6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5,
        0x1ae168fea63dc339a3c58419466ceaeef7f632653266d0e1236431a950cfe52a
      ),
      hex"02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
    );
    // 3G
    assertEq(
      _compress(
        0x04,
        0xf9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9,
        0x388f7b0f632de8140fe337e62a37f3566500a99934c2231b6cb9fd7584b8e672
      ),
      hex"02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9"
    );
    assertEq(_compress(0x04, SMALL_X, SMALL_X_Y), abi.encodePacked(bytes1(0x02), SMALL_X));
    assertEq(_compress(0x04, SMALL_Y_X, SMALL_Y), abi.encodePacked(bytes1(0x03), SMALL_Y_X));
  }

  function testFuzz_compressesValidKey(uint256 privateKey) public {
    privateKey = bound(privateKey, 1, SECP256K1_N - 1);
    Vm.Wallet memory wallet = vm.createWallet(privateKey);
    uint256 x = wallet.publicKeyX;
    uint256 y = wallet.publicKeyY;

    bytes memory compressed = _compress(0x04, x, y);
    assertEq(compressed.length, 33);
    assertEq(compressed, abi.encodePacked(bytes1(y & 1 == 0 ? 0x02 : 0x03), x));

    // The negated point is also on the curve and has the opposite parity
    assertEq(_compress(0x04, x, SECP256K1_P - y), abi.encodePacked(bytes1(y & 1 == 0 ? 0x03 : 0x02), x));
  }

  function test_revokedKeyCompressesToZeroX() public view {
    assertEq(_compress(0x00, 0, 0), abi.encodePacked(bytes1(0x02), bytes32(0)));
  }

  function testFuzz_revert_zeroPrefixWithNonZeroCoordinates(uint256 x, uint256 y) public {
    vm.assume(x != 0 || y != 0);
    _expectInvalid(0x00, x, y);
  }

  function test_revert_zeroPrefixWithValidPoint() public {
    _expectInvalid(0x00, GX, GY);
    _expectInvalid(0x00, GX, 0);
    _expectInvalid(0x00, 0, GY);
    _expectInvalid(0x00, 1, 0);
    _expectInvalid(0x00, 0, 1);
  }

  function testFuzz_revert_invalidPrefix(uint8 prefix, uint256 x, uint256 y) public {
    vm.assume(prefix != 0x00 && prefix != 0x04);
    _expectInvalid(bytes1(prefix), x, y);
  }

  function testFuzz_revert_invalidPrefixWithValidPoint(uint8 prefix) public {
    vm.assume(prefix != 0x00 && prefix != 0x04);
    _expectInvalid(bytes1(prefix), GX, GY);
    _expectInvalid(bytes1(prefix), 0, 0);
  }

  function test_revert_compressedAndHybridPrefixes() public {
    _expectInvalid(0x02, GX, GY);
    _expectInvalid(0x03, GX, SECP256K1_P - GY);
    _expectInvalid(0x06, GX, GY);
    _expectInvalid(0x07, GX, SECP256K1_P - GY);
  }

  function test_revert_zeroPointWithUncompressedPrefix() public {
    _expectInvalid(0x04, 0, 0);
  }

  function testFuzz_revert_xNotInField(uint256 x, uint256 y) public {
    x = bound(x, SECP256K1_P, type(uint256).max);
    _expectInvalid(0x04, x, y);
  }

  function testFuzz_revert_yNotInField(uint256 x, uint256 y) public {
    y = bound(y, SECP256K1_P, type(uint256).max);
    _expectInvalid(0x04, x, y);
  }

  /// @dev `x + p` and `y + p` satisfy the curve equation mod p, so only the range check rejects them
  function test_revert_nonCanonicalCoordinates() public {
    assertTrue(_isOnCurve(SMALL_X + SECP256K1_P, SMALL_X_Y));
    _expectInvalid(0x04, SMALL_X + SECP256K1_P, SMALL_X_Y);

    assertTrue(_isOnCurve(SMALL_Y_X, SMALL_Y + SECP256K1_P));
    _expectInvalid(0x04, SMALL_Y_X, SMALL_Y + SECP256K1_P);

    _expectInvalid(0x04, SECP256K1_P, GY);
    _expectInvalid(0x04, GX, SECP256K1_P);
    _expectInvalid(0x04, type(uint256).max, type(uint256).max);
  }

  function test_fieldBoundary() public {
    // p - 1 passes the range check, so these are rejected (or accepted) by the curve equation alone
    _expectInvalid(0x04, SECP256K1_P - 1, GY);
    _expectInvalid(0x04, GX, SECP256K1_P - 1);
    assertEq(_compress(0x04, SMALL_Y_X, SECP256K1_P - 1), abi.encodePacked(bytes1(0x02), SMALL_Y_X));
  }

  function testFuzz_revert_pointNotOnCurve(uint256 x, uint256 y) public {
    x = bound(x, 0, SECP256K1_P - 1);
    y = bound(y, 0, SECP256K1_P - 1);
    vm.assume(!_isOnCurve(x, y));
    _expectInvalid(0x04, x, y);
  }

  function testFuzz_revert_perturbedValidKey(uint256 privateKey, uint256 delta, bool perturbX) public {
    privateKey = bound(privateKey, 1, SECP256K1_N - 1);
    Vm.Wallet memory wallet = vm.createWallet(privateKey);
    uint256 x = wallet.publicKeyX;
    uint256 y = wallet.publicKeyY;
    if (perturbX) {
      x = addmod(x, bound(delta, 1, SECP256K1_P - 1), SECP256K1_P);
    } else {
      y = addmod(y, bound(delta, 1, SECP256K1_P - 1), SECP256K1_P);
    }
    vm.assume(!_isOnCurve(x, y));
    _expectInvalid(0x04, x, y);
  }

  function test_revert_swappedCoordinates() public {
    _expectInvalid(0x04, GY, GX);
  }
}

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                     UPDATE ASSET TESTS                     */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

contract L1CoreMessaging_UpdateAssetTest is L1CoreMessagingMockBase {
  function test_updateAsset_acceptsPricedOnlyMarginMode() public {
    vm.mockCall(
      zkLighter,
      abi.encodeWithSelector(IZkLighterPublic.assetConfigs.selector, uint16(2)),
      abi.encode(address(0x1234), uint8(1), uint56(1), uint128(1), uint64(1_000_000), uint64(1))
    );

    vm.prank(governor);
    l1CoreMessaging.updateAsset(
      TxTypes.UpdateAsset({
        assetIndex: 2,
        minL2TransferAmount: 1,
        minL2WithdrawalAmount: 1,
        marginMode: uint8(TxTypes.AssetMarginMode.PricedOnly),
        loanToValue: 0,
        liquidationThreshold: 0,
        liquidationFactor: 0,
        liquidationFee: 0,
        indexPriceDivider: 1
      })
    );
  }

  function test_updateAsset_revertsWhenCallerIsNotGovernor() public {
    vm.mockCallRevert(
      governance,
      abi.encodeWithSelector(IGovernance.requireGovernor.selector, other),
      abi.encodeWithSelector(IGovernance.ZkLighter_Governance_OnlyGovernor.selector)
    );

    vm.prank(other);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    l1CoreMessaging.updateAsset(
      TxTypes.UpdateAsset({
        assetIndex: 2,
        minL2TransferAmount: 1,
        minL2WithdrawalAmount: 1,
        marginMode: uint8(TxTypes.AssetMarginMode.Disabled),
        loanToValue: 0,
        liquidationThreshold: 0,
        liquidationFactor: 0,
        liquidationFee: 0,
        indexPriceDivider: 1
      })
    );
  }

  function test_updateAsset_revertsWhenAssetIsInactive() public {
    vm.mockCall(zkLighter, abi.encodeWithSelector(IZkLighterPublic.assetConfigs.selector, uint16(2)), abi.encode(address(0), 0, 0, 0, 0, 0));

    vm.prank(governor);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_AssetNotActive.selector);
    l1CoreMessaging.updateAsset(
      TxTypes.UpdateAsset({
        assetIndex: 2,
        minL2TransferAmount: 1,
        minL2WithdrawalAmount: 1,
        marginMode: uint8(TxTypes.AssetMarginMode.Disabled),
        loanToValue: 0,
        liquidationThreshold: 0,
        liquidationFactor: 0,
        liquidationFee: 0,
        indexPriceDivider: 1
      })
    );
  }
}

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                       REGISTER TESTS                       */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

contract L1CoreMessaging_RegisterTest is L1CoreMessagingMockBase {
  function test_registerAsset_revertsWhenCallerIsNotGovernor() public {
    vm.mockCallRevert(
      governance,
      abi.encodeWithSelector(IGovernance.requireGovernor.selector, other),
      abi.encodeWithSelector(IGovernance.ZkLighter_Governance_OnlyGovernor.selector)
    );
    vm.prank(other);
    vm.expectRevert(IGovernance.ZkLighter_Governance_OnlyGovernor.selector);
    l1CoreMessaging.registerAsset(
      18,
      18,
      6,
      bytes32(0),
      TxTypes.RegisterAsset({
        assetIndex: 2,
        extensionMultiplier: 1,
        minL2TransferAmount: 1,
        minL2WithdrawalAmount: 1,
        marginMode: uint8(TxTypes.AssetMarginMode.Disabled),
        loanToValue: 0,
        liquidationThreshold: 0,
        liquidationFactor: 0,
        liquidationFee: 0,
        indexPriceDivider: 0
      })
    );
  }

  function test_registerAsset_forwardsLegacyMetadataLayout() public {
    TxTypes.RegisterAsset memory params = TxTypes.RegisterAsset({
      assetIndex: 2,
      extensionMultiplier: 44,
      minL2TransferAmount: 11,
      minL2WithdrawalAmount: 22,
      marginMode: uint8(TxTypes.AssetMarginMode.Disabled),
      loanToValue: 0,
      liquidationThreshold: 0,
      liquidationFactor: 0,
      liquidationFee: 0,
      indexPriceDivider: 33
    });
    bytes memory pubData = TxTypes.writeRegisterAssetPubDataForPriorityQueue({
      assetIndex: params.assetIndex,
      extensionMultiplier: params.extensionMultiplier,
      minL2TransferAmount: params.minL2TransferAmount,
      minL2WithdrawalAmount: params.minL2WithdrawalAmount,
      marginMode: params.marginMode,
      loanToValue: params.loanToValue,
      liquidationThreshold: params.liquidationThreshold,
      liquidationFactor: params.liquidationFactor,
      liquidationFee: params.liquidationFee,
      indexPriceDivider: params.indexPriceDivider
    });
    bytes memory metadata = TxTypes.writeRegisterAssetPubDataForPriorityQueueWithMetadata(pubData, 18, 8, 6, 55, address(0x1234), bytes32("UNI"));
    vm.mockCall(
      zkLighter,
      abi.encodeWithSelector(IZkLighterPublic.assetConfigs.selector, uint16(2)),
      abi.encode(address(0x1234), uint8(1), uint56(44), uint128(55), uint64(1_000_000), uint64(1))
    );

    vm.expectCall(
      zkLighter,
      abi.encodeCall(IZkLighter.addPriorityRequestExt, (governor, TxTypes.PriorityPubDataTypeL1RegisterAsset, pubData, metadata))
    );
    vm.expectEmit(address(l1CoreMessaging));
    emit L1CoreMessaging.RegisterAsset(params, 18, 8, 6, bytes32("UNI"));

    vm.prank(governor);
    l1CoreMessaging.registerAsset(18, 8, 6, bytes32("UNI"), params);
  }
}

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                   SET SYSTEM CONFIG TESTS                  */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

contract L1CoreMessaging_SetSystemConfigTest is L1CoreMessagingMockBase {
  function test_setSystemConfig_queuesRequestAndEmitsTypedEvent() public {
    TxTypes.SetSystemConfig memory params = TxTypes.SetSystemConfig({
      liquidityPoolIndex: 10,
      stakingPoolIndex: 11,
      liquidityPoolCooldownPeriod: 1000,
      stakingPoolLockupPeriod: 2000,
      maxIntegratorPerpsTakerFee: 10,
      maxIntegratorPerpsMakerFee: 10,
      maxIntegratorSpotTakerFee: 1000,
      maxIntegratorSpotMakerFee: 20
    });
    bytes memory pubData = TxTypes.writeSetSystemConfigPubDataForPriorityQueue({
      liquidityPoolIndex: params.liquidityPoolIndex,
      stakingPoolIndex: params.stakingPoolIndex,
      liquidityPoolCooldownPeriod: params.liquidityPoolCooldownPeriod,
      stakingPoolLockupPeriod: params.stakingPoolLockupPeriod,
      maxIntegratorPerpsTakerFee: params.maxIntegratorPerpsTakerFee,
      maxIntegratorPerpsMakerFee: params.maxIntegratorPerpsMakerFee,
      maxIntegratorSpotTakerFee: params.maxIntegratorSpotTakerFee,
      maxIntegratorSpotMakerFee: params.maxIntegratorSpotMakerFee
    });

    vm.expectCall(
      zkLighter,
      abi.encodeCall(IZkLighter.addPriorityRequestExt, (governor, TxTypes.PriorityPubDataTypeL1SetSystemConfig, pubData, pubData))
    );
    vm.expectEmit(address(l1CoreMessaging));
    emit L1CoreMessaging.SetSystemConfig(params);

    vm.prank(governor);
    l1CoreMessaging.setSystemConfig(params);
  }
}

contract L1CoreMessaging_IntegrationTest is Test {
  function test_tokensStayOnZkLighterWhileCoreMessagingQueuesNonTokenWrites() public {
    ZkLighterTest zkLighter = new ZkLighterTest();
    GovernanceTest governanceContract = new GovernanceTest();
    AdditionalZkLighter additional = new AdditionalZkLighter();
    SimpleERC20 token = new SimpleERC20("Token", "TOK");
    SimpleERC20 usdc = new SimpleERC20("USD Coin", "USDC");
    address userAccount = makeAddr("integrationUser");

    governanceContract.overrideNetworkGovernor(address(this));
    governanceContract.overrideUSDCAddress(usdc);
    zkLighter.setGovernanceAddress(address(governanceContract));
    zkLighter.setAdditionalZkLighterAddress(address(additional));
    zkLighter.setLastAccountIndex(2);
    zkLighter.setTreasury(makeAddr("treasury"));
    zkLighter.setInsuranceFundOperator(makeAddr("insuranceFundOperator"));
    zkLighter.registerDefaultAssetConfigs();
    zkLighter.registerAssetConfig(2, address(token), 1, 1, 1, 1_000_000, 1);

    L1CoreMessaging implementation = new L1CoreMessaging();
    L1CoreMessaging coreMessaging = L1CoreMessaging(
      address(new Proxy(address(implementation), abi.encode(address(zkLighter), address(governanceContract))))
    );
    zkLighter.setCoreMessaging(address(coreMessaging));

    token.mint(userAccount, 10);
    vm.startPrank(userAccount);
    token.approve(address(zkLighter), 10);
    zkLighter.depositTest(userAccount, 2, TxTypes.RouteType.Perps, 10);
    coreMessaging.cancelAllOrders(3);
    vm.stopPrank();

    address batchSender = makeAddr("batchSender");
    address[] memory recipients = new address[](2);
    recipients[0] = makeAddr("batchRecipient0");
    recipients[1] = makeAddr("batchRecipient1");
    uint64[] memory amounts = new uint64[](2);
    amounts[0] = 1_000_000;
    amounts[1] = 1_000_000;
    uint48[] memory accountIndexes = new uint48[](2);
    usdc.mint(batchSender, 2_000_000);
    vm.startPrank(batchSender);
    usdc.approve(address(zkLighter), 2_000_000);
    zkLighter.depositBatchTest(amounts, recipients, accountIndexes);
    vm.stopPrank();

    assertEq(token.balanceOf(address(zkLighter)), 10);
    assertEq(usdc.balanceOf(address(zkLighter)), 2_000_000);
    assertEq(token.balanceOf(address(coreMessaging)), 0);
    assertEq(zkLighter.addressToAccountIndex(userAccount), 3);
    assertEq(zkLighter.addressToAccountIndex(recipients[0]), 4);
    assertEq(zkLighter.addressToAccountIndex(recipients[1]), 5);
    assertEq(zkLighter.openPriorityRequestCount(), 4);

    // L1CoreMessaging does not duplicate the desert-mode check. The P1
    // ZkLighter forwarding boundary remains the source of truth.
    zkLighter.setDesertMode(true);
    vm.prank(userAccount);
    vm.expectRevert(IZkLighterDesertMode.ZkLighter_DesertModeActive.selector);
    coreMessaging.cancelAllOrders(3);
    assertEq(zkLighter.openPriorityRequestCount(), 4);
  }

  function test_addPriorityRequestExtRejectsEther() public {
    ZkLighterTest zkLighter = new ZkLighterTest();
    address coreMessaging = makeAddr("coreMessaging");
    zkLighter.setCoreMessaging(coreMessaging);
    vm.deal(coreMessaging, 1 ether);

    bytes memory callData = abi.encodeCall(IZkLighter.addPriorityRequestExt, (coreMessaging, TxTypes.PriorityPubDataTypeL1CancelAllOrders, "", ""));
    vm.startPrank(coreMessaging);
    (bool successWithValue, ) = address(zkLighter).call{value: 1}(callData);
    (bool successWithoutValue, ) = address(zkLighter).call(callData);
    vm.stopPrank();

    assertFalse(successWithValue);
    assertTrue(successWithoutValue);
  }
}

contract L1CoreMessaging_PubDataAllowlistTest is Test {
  ZkLighterTest zkLighter;
  address coreMessaging = makeAddr("coreMessaging");

  function setUp() public {
    zkLighter = new ZkLighterTest();
    zkLighter.setAdditionalZkLighterAddress(address(new AdditionalZkLighter()));
    zkLighter.setCoreMessaging(coreMessaging);
  }

  function _allowedTypes() internal pure returns (uint8[11] memory) {
    return [
      TxTypes.PriorityPubDataTypeL1ChangePubKey,
      TxTypes.PriorityPubDataTypeL1CreateMarket,
      TxTypes.PriorityPubDataTypeL1UpdateMarket,
      TxTypes.PriorityPubDataTypeL1CancelAllOrders,
      TxTypes.PriorityPubDataTypeL1Withdraw,
      TxTypes.PriorityPubDataTypeL1CreateOrder,
      TxTypes.PriorityPubDataTypeL1BurnShares,
      TxTypes.PriorityPubDataTypeL1RegisterAsset,
      TxTypes.PriorityPubDataTypeL1UpdateAsset,
      TxTypes.PriorityPubDataTypeL1SetSystemConfig,
      TxTypes.PriorityPubDataTypeL1ChangeECDSAPubKey
    ];
  }

  function _isAllowed(uint8 pubdataType) internal pure returns (bool) {
    uint8[11] memory allowed = _allowedTypes();
    for (uint256 i = 0; i < allowed.length; i++) {
      if (allowed[i] == pubdataType) return true;
    }
    return false;
  }

  function _add(uint8 pubdataType, bytes memory pubData) internal {
    vm.prank(coreMessaging);
    zkLighter.addPriorityRequestExt(coreMessaging, pubdataType, pubData, pubData);
  }

  function _expectInvalid(uint8 pubdataType, bytes memory pubData) internal {
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidCoreMessagingPubData.selector);
    _add(pubdataType, pubData);
  }

  function test_acceptsEveryAllowedType() public {
    uint8[11] memory allowed = _allowedTypes();
    for (uint256 i = 0; i < allowed.length; i++) {
      _add(allowed[i], abi.encodePacked(allowed[i], uint48(3), uint48(3)));
    }
    assertEq(zkLighter.openPriorityRequestCount(), allowed.length);
  }

  function testFuzz_rejectsTypesOutsideAllowlist(uint8 pubdataType) public {
    vm.assume(!_isAllowed(pubdataType));
    _expectInvalid(pubdataType, abi.encodePacked(pubdataType, uint48(3), uint48(3)));
    assertEq(zkLighter.openPriorityRequestCount(), 0);
  }

  function test_rejectsDeposit() public {
    bytes memory deposit = abi.encodePacked(
      TxTypes.PriorityPubDataTypeL1Deposit,
      uint48(3),
      makeAddr("user"),
      uint16(3),
      uint8(TxTypes.RouteType.Perps),
      uint64(1e12)
    );
    assertEq(deposit.length, TxTypes.DEPOSIT_PUB_DATA_SIZE);
    _expectInvalid(TxTypes.PriorityPubDataTypeL1Deposit, deposit);
  }

  function test_rejectsUnstakeAssets() public {
    _expectInvalid(TxTypes.PriorityPubDataTypeL1UnstakeAssets, abi.encodePacked(TxTypes.PriorityPubDataTypeL1UnstakeAssets, uint48(3)));
  }

  function test_rejectsDepositPayloadUnderAllowedType() public {
    bytes memory deposit = abi.encodePacked(TxTypes.PriorityPubDataTypeL1Deposit, uint48(3), makeAddr("user"), uint16(3), uint8(0), uint64(1e12));
    _expectInvalid(TxTypes.PriorityPubDataTypeL1Withdraw, deposit);
  }

  function testFuzz_rejectsTypeByteMismatch(uint8 allowedIdx, uint8 payloadType) public {
    uint8 pubdataType = _allowedTypes()[bound(allowedIdx, 0, 10)];
    vm.assume(payloadType != pubdataType);
    _expectInvalid(pubdataType, abi.encodePacked(payloadType, uint48(3), uint48(3)));
  }

  function test_rejectsEmptyAndOversizedPubData() public {
    uint8 pubdataType = TxTypes.PriorityPubDataTypeL1CancelAllOrders;
    _expectInvalid(pubdataType, "");

    bytes memory oversized = new bytes(101);
    oversized[0] = bytes1(pubdataType);
    _expectInvalid(pubdataType, oversized);

    bytes memory maxSize = new bytes(100);
    maxSize[0] = bytes1(pubdataType);
    _add(pubdataType, maxSize);
    assertEq(zkLighter.openPriorityRequestCount(), 1);
  }
}

contract L1CoreMessaging_UpgradeTest is L1CoreMessagingMockBase {
  function test_proxyMasterCanUpgradeTarget() public {
    L1CoreMessaging newImplementation = new L1CoreMessaging();

    Proxy proxy = Proxy(payable(address(l1CoreMessaging)));
    proxy.upgradeTarget(address(newImplementation), "");
    assertEq(proxy.getTarget(), address(newImplementation));
  }

  function test_upgradeIsInterceptedOnProxy() public {
    vm.expectRevert(bytes("upg11"));
    l1CoreMessaging.upgrade("");
  }
}

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                       WITHDRAW TESTS                       */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

contract L1CoreMessaging_WithdrawTest is L1CoreMessagingMockBase {
  function test_withdraw_usesCallerAccount() public {
    vm.mockCall(zkLighter, abi.encodeWithSelector(IZkLighterPublic.addressToAccountIndex.selector, user), abi.encode(uint48(7)));
    vm.mockCall(
      zkLighter,
      abi.encodeWithSelector(IZkLighterPublic.assetConfigs.selector, uint16(2)),
      abi.encode(address(0x2222), uint8(1), uint56(1), uint128(1), uint64(100), uint64(1))
    );
    vm.prank(user);
    l1CoreMessaging.withdraw(8, 2, TxTypes.RouteType.Perps, 10);
  }

  function test_withdraw_revertsWhenAccountIndexTooLarge() public {
    vm.prank(user);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidAccountIndex.selector);
    l1CoreMessaging.withdraw(type(uint48).max, 2, TxTypes.RouteType.Perps, 10);
  }

  function test_withdraw_revertsWhenAssetInactive() public {
    vm.mockCall(
      zkLighter,
      abi.encodeWithSelector(IZkLighterPublic.assetConfigs.selector, uint16(2)),
      abi.encode(address(0x2222), uint8(0), uint56(1), uint128(1), uint64(100), uint64(1))
    );

    vm.prank(user);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_AssetNotActive.selector);
    l1CoreMessaging.withdraw(8, 2, TxTypes.RouteType.Perps, 10);
  }

  function test_withdraw_revertsWhenAmountZero() public {
    vm.mockCall(
      zkLighter,
      abi.encodeWithSelector(IZkLighterPublic.assetConfigs.selector, uint16(2)),
      abi.encode(address(0x2222), uint8(1), uint56(1), uint128(1), uint64(100), uint64(1))
    );

    vm.prank(user);
    vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidWithdrawAmount.selector);
    l1CoreMessaging.withdraw(8, 2, TxTypes.RouteType.Perps, 0);
  }
}

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                 SYSTEM ACCOUNT SETTER TESTS                */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*              ASSET PARAMETER VALIDATION TESTS              */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/// Exercises `_validateCommonAssetParams` through both `registerAsset` and `updateAsset`.
contract L1CoreMessaging_AssetParamsTest is L1CoreMessagingMockBase, Config {
  uint16 constant ASSET = 2;
  uint32 constant FEE_PER_MARGIN_TICK = FEE_TICK / ASSET_MARGIN_TICK; // 100

  struct Margin {
    uint8 mode;
    uint16 ltv;
    uint16 threshold;
    uint16 factor;
    uint32 fee;
  }

  function setUp() public override {
    super.setUp();
    _mockRegistered(ASSET);
    _mockRegistered(USDC_ASSET_INDEX);
  }

  function _mockRegistered(uint16 assetIndex) internal {
    vm.mockCall(
      zkLighter,
      abi.encodeWithSelector(IZkLighterPublic.assetConfigs.selector, assetIndex),
      abi.encode(address(0x1234), uint8(1), uint56(1), uint128(1), uint64(1_000_000), uint64(1))
    );
  }

  function _disabled() internal pure returns (Margin memory) {
    return Margin(uint8(TxTypes.AssetMarginMode.Disabled), 0, 0, 0, 0);
  }

  function _enabled() internal pure returns (Margin memory) {
    return Margin(uint8(TxTypes.AssetMarginMode.Enabled), 7_000, 8_000, 9_000, 50_000);
  }

  function _update(uint16 assetIndex, uint64 minTransfer, uint64 minWithdrawal, Margin memory m) internal {
    vm.prank(governor);
    l1CoreMessaging.updateAsset(
      TxTypes.UpdateAsset({
        assetIndex: assetIndex,
        minL2TransferAmount: minTransfer,
        minL2WithdrawalAmount: minWithdrawal,
        marginMode: m.mode,
        loanToValue: m.ltv,
        liquidationThreshold: m.threshold,
        liquidationFactor: m.factor,
        liquidationFee: m.fee,
        indexPriceDivider: 1
      })
    );
  }

  function _register(uint16 assetIndex, uint64 minTransfer, uint64 minWithdrawal, Margin memory m) internal {
    vm.prank(governor);
    l1CoreMessaging.registerAsset(
      18,
      18,
      6,
      bytes32("TKN"),
      TxTypes.RegisterAsset({
        assetIndex: assetIndex,
        extensionMultiplier: 1,
        minL2TransferAmount: minTransfer,
        minL2WithdrawalAmount: minWithdrawal,
        marginMode: m.mode,
        loanToValue: m.ltv,
        liquidationThreshold: m.threshold,
        liquidationFactor: m.factor,
        liquidationFee: m.fee,
        indexPriceDivider: 1
      })
    );
  }

  function _expectUpdateRevert(bytes4 selector, uint16 assetIndex, uint64 minTransfer, uint64 minWithdrawal, Margin memory m) internal {
    vm.expectRevert(selector);
    _update(assetIndex, minTransfer, minWithdrawal, m);
  }

  function _expectRegisterRevert(bytes4 selector, uint16 assetIndex, uint64 minTransfer, uint64 minWithdrawal, Margin memory m) internal {
    vm.expectRevert(selector);
    _register(assetIndex, minTransfer, minWithdrawal, m);
  }

  // ---------- min transfer / withdrawal ----------

  function test_minAmounts_rejectZeroAndAboveCap() public {
    bytes4 transferSel = L1CoreMessaging.L1CoreMessaging_InvalidMinL2TransferAmount.selector;
    bytes4 withdrawSel = L1CoreMessaging.L1CoreMessaging_InvalidMinL2WithdrawalAmount.selector;

    _expectUpdateRevert(transferSel, ASSET, 0, 1, _disabled());
    _expectUpdateRevert(transferSel, ASSET, MAX_DEPOSIT_CAP_TICKS + 1, 1, _disabled());
    _expectUpdateRevert(withdrawSel, ASSET, 1, 0, _disabled());
    _expectUpdateRevert(withdrawSel, ASSET, 1, MAX_DEPOSIT_CAP_TICKS + 1, _disabled());

    _expectRegisterRevert(transferSel, ASSET, 0, 1, _disabled());
    _expectRegisterRevert(withdrawSel, ASSET, 1, 0, _disabled());

    // Boundary values are accepted.
    _update(ASSET, MAX_DEPOSIT_CAP_TICKS, MAX_DEPOSIT_CAP_TICKS, _disabled());
    _register(ASSET, MAX_DEPOSIT_CAP_TICKS, MAX_DEPOSIT_CAP_TICKS, _disabled());
  }

  // ---------- margin enabled ----------

  function test_marginEnabled_validParamsAccepted() public {
    _update(ASSET, 1, 1, _enabled());
    _register(ASSET, 1, 1, _enabled());

    // Equalities are allowed: ltv == threshold == factor == ASSET_MARGIN_TICK with zero fee.
    _update(ASSET, 1, 1, Margin(uint8(TxTypes.AssetMarginMode.Enabled), ASSET_MARGIN_TICK, ASSET_MARGIN_TICK, ASSET_MARGIN_TICK, 0));

    // Fee exactly at the cap: fee + factor * 100 == FEE_TICK.
    uint16 factor = 9_000;
    uint32 maxFee = FEE_TICK - uint32(factor) * FEE_PER_MARGIN_TICK;
    _update(ASSET, 1, 1, Margin(uint8(TxTypes.AssetMarginMode.Enabled), 1, factor, factor, maxFee));
  }

  function test_marginEnabled_rejectsZeroLoanToValue() public {
    Margin memory m = _enabled();
    m.ltv = 0;
    _expectUpdateRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarginParameters.selector, ASSET, 1, 1, m);
    _expectRegisterRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarginParameters.selector, ASSET, 1, 1, m);
  }

  function test_marginEnabled_rejectsLoanToValueAboveThreshold() public {
    Margin memory m = _enabled();
    m.ltv = m.threshold + 1;
    _expectUpdateRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarginParameters.selector, ASSET, 1, 1, m);
  }

  function test_marginEnabled_rejectsThresholdAboveFactor() public {
    Margin memory m = _enabled();
    m.threshold = m.factor + 1;
    m.ltv = m.threshold;
    _expectUpdateRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarginParameters.selector, ASSET, 1, 1, m);
  }

  function test_marginEnabled_rejectsFactorAboveMarginTick() public {
    Margin memory m = _enabled();
    m.factor = ASSET_MARGIN_TICK + 1;
    m.fee = 0;
    _expectUpdateRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarginParameters.selector, ASSET, 1, 1, m);
  }

  function test_marginEnabled_rejectsFeeExceedingBudget() public {
    uint16 factor = 9_000;
    uint32 maxFee = FEE_TICK - uint32(factor) * FEE_PER_MARGIN_TICK;
    Margin memory m = Margin(uint8(TxTypes.AssetMarginMode.Enabled), 1, factor, factor, maxFee + 1);
    _expectUpdateRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarginParameters.selector, ASSET, 1, 1, m);
    _expectRegisterRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarginParameters.selector, ASSET, 1, 1, m);
  }

  function testFuzz_marginEnabled_orderingInvariant(uint16 ltv, uint16 threshold, uint16 factor, uint32 fee) public {
    ltv = uint16(bound(ltv, 0, ASSET_MARGIN_TICK + 1));
    threshold = uint16(bound(threshold, 0, ASSET_MARGIN_TICK + 1));
    factor = uint16(bound(factor, 0, ASSET_MARGIN_TICK + 1));
    fee = uint32(bound(fee, 0, FEE_TICK + 1));

    bool orderingOk = ltv != 0 && ltv <= threshold && threshold <= factor && factor <= ASSET_MARGIN_TICK;
    bool feeOk = uint256(fee) + uint256(factor) * FEE_PER_MARGIN_TICK <= FEE_TICK;
    Margin memory m = Margin(uint8(TxTypes.AssetMarginMode.Enabled), ltv, threshold, factor, fee);

    if (!(orderingOk && feeOk)) {
      vm.expectRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarginParameters.selector);
    }
    _update(ASSET, 1, 1, m);
  }

  // ---------- USDC ----------

  function test_usdc_mustBeMarginEnabledWithFullLtvAndZeroFee() public {
    bytes4 sel = L1CoreMessaging.L1CoreMessaging_InvalidMarginParameters.selector;

    _update(USDC_ASSET_INDEX, 1, 1, Margin(uint8(TxTypes.AssetMarginMode.Enabled), ASSET_MARGIN_TICK, ASSET_MARGIN_TICK, ASSET_MARGIN_TICK, 0));

    _expectUpdateRevert(
      sel,
      USDC_ASSET_INDEX,
      1,
      1,
      Margin(uint8(TxTypes.AssetMarginMode.Enabled), ASSET_MARGIN_TICK - 1, ASSET_MARGIN_TICK, ASSET_MARGIN_TICK, 0)
    );
    _expectUpdateRevert(
      sel,
      USDC_ASSET_INDEX,
      1,
      1,
      Margin(uint8(TxTypes.AssetMarginMode.Enabled), ASSET_MARGIN_TICK, ASSET_MARGIN_TICK, ASSET_MARGIN_TICK, 1)
    );
    _expectUpdateRevert(sel, USDC_ASSET_INDEX, 1, 1, _disabled());
    _expectUpdateRevert(sel, USDC_ASSET_INDEX, 1, 1, Margin(uint8(TxTypes.AssetMarginMode.PricedOnly), 0, 0, 0, 0));
  }

  // ---------- disabled / priced-only ----------

  function test_disabledOrPricedOnly_rejectNonZeroMarginFields() public {
    bytes4 sel = L1CoreMessaging.L1CoreMessaging_InvalidMarginParameters.selector;
    uint8[2] memory modes = [uint8(TxTypes.AssetMarginMode.Disabled), uint8(TxTypes.AssetMarginMode.PricedOnly)];
    for (uint256 i = 0; i < modes.length; ++i) {
      _update(ASSET, 1, 1, Margin(modes[i], 0, 0, 0, 0));
      _expectUpdateRevert(sel, ASSET, 1, 1, Margin(modes[i], 1, 0, 0, 0));
      _expectUpdateRevert(sel, ASSET, 1, 1, Margin(modes[i], 0, 1, 0, 0));
      _expectUpdateRevert(sel, ASSET, 1, 1, Margin(modes[i], 0, 0, 1, 0));
      _expectUpdateRevert(sel, ASSET, 1, 1, Margin(modes[i], 0, 0, 0, 1));
      _expectRegisterRevert(sel, ASSET, 1, 1, Margin(modes[i], 1, 0, 0, 0));
    }
  }

  function testFuzz_unknownMarginMode_rejected(uint8 mode) public {
    vm.assume(mode > uint8(TxTypes.AssetMarginMode.PricedOnly));
    _expectUpdateRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarginParameters.selector, ASSET, 1, 1, Margin(mode, 0, 0, 0, 0));
    _expectRegisterRevert(L1CoreMessaging.L1CoreMessaging_InvalidMarginParameters.selector, ASSET, 1, 1, Margin(mode, 0, 0, 0, 0));
  }

  // ---------- pubdata forwarding for a margin-enabled asset ----------

  function test_marginEnabled_forwardsParamsInPubData() public {
    Margin memory m = _enabled();
    TxTypes.UpdateAsset memory params = TxTypes.UpdateAsset({
      assetIndex: ASSET,
      minL2TransferAmount: 1,
      minL2WithdrawalAmount: 1,
      marginMode: m.mode,
      loanToValue: m.ltv,
      liquidationThreshold: m.threshold,
      liquidationFactor: m.factor,
      liquidationFee: m.fee,
      indexPriceDivider: 1
    });
    bytes memory pubData = TxTypes.writeUpdateAssetPubDataForPriorityQueue({
      assetIndex: params.assetIndex,
      minL2TransferAmount: params.minL2TransferAmount,
      minL2WithdrawalAmount: params.minL2WithdrawalAmount,
      marginMode: params.marginMode,
      loanToValue: params.loanToValue,
      liquidationThreshold: params.liquidationThreshold,
      liquidationFactor: params.liquidationFactor,
      liquidationFee: params.liquidationFee,
      indexPriceDivider: params.indexPriceDivider
    });
    vm.expectCall(
      zkLighter,
      abi.encodeCall(IZkLighter.addPriorityRequestExt, (governor, TxTypes.PriorityPubDataTypeL1UpdateAsset, pubData, pubData))
    );
    vm.expectEmit(address(l1CoreMessaging));
    emit L1CoreMessaging.UpdateAsset(params);
    _update(ASSET, 1, 1, m);
  }
}
