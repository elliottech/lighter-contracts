// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import {ZkLighterFixture} from "./helpers/ZkLighterFixture.sol";
import {AdditionalZkLighter} from "../contracts/AdditionalZkLighter.sol";
import {TxTypes} from "../contracts/lib/TxTypes.sol";

contract ZkLighterMarketTests is ZkLighterFixture {
  bytes32 internal constant BTC = bytes32("BTC");
  bytes32 internal constant ETH_USDC = bytes32("ETH/USDC");

  function test_createPerpsMarketSucceedsAndEmits() public {
    PerpsData memory data = _validPerpsData();
    TxTypes.CreateMarket memory params = _createPerpsParams(1, data);
    bytes memory priorityData = TxTypes.writeCreateMarketPubDataForPriorityQueue(params);
    bytes memory eventData = TxTypes.writeCreateMarketPubDataForPriorityQueueWithMetadata(priorityData, 3, 3, BTC);
    _expectPriorityEvent(address(this), 0, TxTypes.PriorityPubDataTypeL1CreateMarket, eventData);
    vm.expectEmit(false, false, false, true, address(zklighter));
    emit CreateMarket(params, 3, 3, BTC);

    zklighter.createMarket(3, 3, BTC, params);
  }

  function test_createPerpsMarketRejectsInvalidIndex() public {
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketType.selector);
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(255, PerpsData(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)));
  }

  function test_createPerpsMarketRejectsSpotIndex() public {
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketType.selector);
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(2049, PerpsData(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)));
  }

  function test_createPerpsMarketRejectsInvalidQuoteMultiplier() public {
    PerpsData memory data;
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidExtensionMultiplier.selector);
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));

    data.quoteMultiplier = 1_000_001;
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidExtensionMultiplier.selector);
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));
  }

  function test_createPerpsMarketRejectsInvalidFees() public {
    PerpsData memory data;
    data.quoteMultiplier = 1;
    data.makerFee = 1_000_001;
    _expectInvalidFee();
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));

    data.makerFee = 1;
    data.takerFee = 1_000_001;
    _expectInvalidFee();
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));

    data.takerFee = 1;
    data.liquidationFee = 1_000_001;
    _expectInvalidFee();
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));
  }

  function test_createPerpsMarketRejectsInvalidMargins() public {
    PerpsData memory data;
    data.quoteMultiplier = 1;
    _expectGenericMarketError();
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));

    data.closeOutMarginFraction = 1;
    _expectGenericMarketError();
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));

    data.maintenanceMarginFraction = 1;
    _expectGenericMarketError();
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));

    data.minInitialMarginFraction = 1;
    _expectGenericMarketError();
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));

    data.defaultInitialMarginFraction = 10_001;
    _expectGenericMarketError();
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));
  }

  function test_createPerpsMarketRejectsInvalidInterestRate() public {
    PerpsData memory data;
    data.quoteMultiplier = 1;
    data.closeOutMarginFraction = 1;
    data.maintenanceMarginFraction = 1;
    data.minInitialMarginFraction = 1;
    data.defaultInitialMarginFraction = 1;
    data.interestRate = 1_000_001;
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidFundingClampsOrInterestRate.selector);
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));
  }

  function test_createPerpsMarketRejectsInvalidMinAmounts() public {
    PerpsData memory data;
    data.quoteMultiplier = 1;
    data.closeOutMarginFraction = 1;
    data.maintenanceMarginFraction = 1;
    data.minInitialMarginFraction = 1;
    data.defaultInitialMarginFraction = 1;
    data.interestRate = 1;
    data.minBaseAmount = type(uint48).max;
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMinAmounts.selector);
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));

    data.minBaseAmount = 1;
    data.minQuoteAmount = type(uint48).max;
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketLimits.selector);
    zklighter.createMarket(1, 1, BTC, _createPerpsParams(1, data));
  }

  function test_createSpotMarketSucceedsAndEmits() public {
    SpotData memory data = _validSpotData();
    TxTypes.CreateMarket memory params = _createSpotParams(2048, data);
    bytes memory priorityData = TxTypes.writeCreateMarketPubDataForPriorityQueue(params);
    bytes memory eventData = TxTypes.writeCreateMarketPubDataForPriorityQueueWithMetadata(priorityData, 3, 3, ETH_USDC);
    _expectPriorityEvent(address(this), 0, TxTypes.PriorityPubDataTypeL1CreateMarket, eventData);
    vm.expectEmit(false, false, false, true, address(zklighter));
    emit CreateMarket(params, 3, 3, ETH_USDC);

    zklighter.createMarket(3, 3, ETH_USDC, params);
  }

  function test_createSpotMarketRejectsInvalidAssets() public {
    SpotData memory data;
    data.baseAssetIndex = 1;
    data.quoteAssetIndex = 1;
    _expectInvalidAsset();
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(2049, data));

    data.baseAssetIndex = 0;
    data.quoteAssetIndex = 1;
    _expectInvalidAsset();
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(2049, data));

    data.baseAssetIndex = 1;
    data.quoteAssetIndex = 59;
    _expectInvalidAsset();
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(2049, data));
  }

  function test_createSpotMarketRejectsInvalidIndex() public {
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketType.selector);
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(255, SpotData(0, 0, 0, 0, 0, 0, 0, 0, 0)));
  }

  function test_createSpotMarketRejectsPerpsIndex() public {
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketType.selector);
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(1, SpotData(0, 0, 0, 0, 0, 0, 0, 0, 0)));
  }

  function test_createSpotMarketRejectsInvalidExtensionMultipliers() public {
    SpotData memory data;
    data.baseAssetIndex = 1;
    data.quoteAssetIndex = 3;
    data.sizeExtensionMultiplier = 1_000_000;
    _expectInvalidExtensionMultiplier();
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(2049, data));

    data.quoteExtensionMultiplier = 1;
    _expectInvalidExtensionMultiplier();
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(2049, data));

    data.quoteExtensionMultiplier = 1_000_000;
    data.sizeExtensionMultiplier = 0;
    _expectInvalidExtensionMultiplier();
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(2049, data));

    data.sizeExtensionMultiplier = 1;
    _expectInvalidExtensionMultiplier();
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(2049, data));
  }

  function test_createSpotMarketRejectsInvalidFees() public {
    SpotData memory data;
    data.baseAssetIndex = 1;
    data.quoteAssetIndex = 3;
    data.sizeExtensionMultiplier = 1_000_000;
    data.quoteExtensionMultiplier = 1_000_000;
    data.makerFee = 1_000_001;
    _expectInvalidFee();
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(2049, data));

    data.makerFee = 1;
    data.takerFee = 1_000_001;
    _expectInvalidFee();
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(2049, data));
  }

  function test_createSpotMarketRejectsInvalidMinAmounts() public {
    SpotData memory data;
    data.baseAssetIndex = 1;
    data.quoteAssetIndex = 3;
    data.sizeExtensionMultiplier = 1_000_000;
    data.quoteExtensionMultiplier = 1_000_000;
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMinAmounts.selector);
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(2049, data));

    data.minBaseAmount = 1;
    data.minQuoteAmount = type(uint48).max;
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketLimits.selector);
    zklighter.createMarket(1, 1, ETH_USDC, _createSpotParams(2049, data));
  }

  function test_updatePerpsMarketSucceedsAndEmits() public {
    PerpsData memory data = _validPerpsData();
    data.takerFee = 0;
    data.makerFee = 0;
    data.liquidationFee = 0;
    TxTypes.UpdateMarket memory params = _updatePerpsParams(10, 1, data);
    _expectPriorityEvent(address(this), 0, TxTypes.PriorityPubDataTypeL1UpdateMarket, TxTypes.writeUpdateMarketPubDataForPriorityQueue(params));
    vm.expectEmit(false, false, false, true, address(zklighter));
    emit UpdateMarket(params);

    zklighter.updateMarket(params);
  }

  function test_updatePerpsMarketRejectsInvalidIndex() public {
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketType.selector);
    zklighter.updateMarket(_updatePerpsParams(255, 0, PerpsData(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)));
  }

  function test_updatePerpsMarketRejectsSpotIndex() public {
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketType.selector);
    zklighter.updateMarket(_updatePerpsParams(2049, 0, PerpsData(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)));
  }

  function test_updatePerpsMarketRejectsInvalidStatus() public {
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketStatus.selector);
    zklighter.updateMarket(_updatePerpsParams(1, 3, PerpsData(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)));
  }

  function test_updatePerpsMarketRejectsInvalidFees() public {
    PerpsData memory data;
    data.makerFee = 1_000_001;
    _expectInvalidFee();
    zklighter.updateMarket(_updatePerpsParams(1, 0, data));

    data.makerFee = 1;
    data.takerFee = 1_000_001;
    _expectInvalidFee();
    zklighter.updateMarket(_updatePerpsParams(1, 0, data));

    data.takerFee = 1;
    data.liquidationFee = 1_000_001;
    _expectInvalidFee();
    zklighter.updateMarket(_updatePerpsParams(1, 0, data));
  }

  function test_updatePerpsMarketRejectsInvalidMargins() public {
    PerpsData memory data;
    _expectGenericMarketError();
    zklighter.updateMarket(_updatePerpsParams(1, 0, data));

    data.closeOutMarginFraction = 1;
    _expectGenericMarketError();
    zklighter.updateMarket(_updatePerpsParams(1, 0, data));

    data.maintenanceMarginFraction = 1;
    _expectGenericMarketError();
    zklighter.updateMarket(_updatePerpsParams(1, 0, data));

    data.minInitialMarginFraction = 1;
    _expectGenericMarketError();
    zklighter.updateMarket(_updatePerpsParams(1, 0, data));

    data.defaultInitialMarginFraction = 10_001;
    _expectGenericMarketError();
    zklighter.updateMarket(_updatePerpsParams(1, 0, data));
  }

  function test_updatePerpsMarketRejectsInvalidInterestRate() public {
    PerpsData memory data;
    data.closeOutMarginFraction = 1;
    data.maintenanceMarginFraction = 1;
    data.minInitialMarginFraction = 1;
    data.defaultInitialMarginFraction = 1;
    data.interestRate = 1_000_001;
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidFundingClampsOrInterestRate.selector);
    zklighter.updateMarket(_updatePerpsParams(1, 0, data));
  }

  function test_updatePerpsMarketRejectsInvalidMinAmounts() public {
    PerpsData memory data;
    data.closeOutMarginFraction = 1;
    data.maintenanceMarginFraction = 1;
    data.minInitialMarginFraction = 1;
    data.defaultInitialMarginFraction = 1;
    data.interestRate = 1;
    data.minBaseAmount = type(uint48).max;
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMinAmounts.selector);
    zklighter.updateMarket(_updatePerpsParams(1, 0, data));

    data.minBaseAmount = 1;
    data.minQuoteAmount = type(uint48).max;
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketLimits.selector);
    zklighter.updateMarket(_updatePerpsParams(1, 0, data));
  }

  function test_updateSpotMarketSucceedsAndEmits() public {
    UpdateSpotData memory data = UpdateSpotData(1, 0, 0, 1, 1, 1);
    TxTypes.UpdateMarket memory params = _updateSpotParams(2049, data);
    _expectPriorityEvent(address(this), 0, TxTypes.PriorityPubDataTypeL1UpdateMarket, TxTypes.writeUpdateMarketPubDataForPriorityQueue(params));
    vm.expectEmit(false, false, false, true, address(zklighter));
    emit UpdateMarket(params);

    zklighter.updateMarket(params);
  }

  function test_updateSpotMarketRejectsInvalidIndex() public {
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketType.selector);
    zklighter.updateMarket(_updateSpotParams(255, UpdateSpotData(0, 0, 0, 0, 0, 0)));
  }

  function test_updateSpotMarketRejectsPerpsIndex() public {
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketType.selector);
    zklighter.updateMarket(_updateSpotParams(1, UpdateSpotData(0, 0, 0, 0, 0, 0)));
  }

  function test_updateSpotMarketRejectsInvalidStatus() public {
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketStatus.selector);
    zklighter.updateMarket(_updateSpotParams(2049, UpdateSpotData(3, 0, 0, 0, 0, 0)));
  }

  function test_updateSpotMarketRejectsInvalidFees() public {
    UpdateSpotData memory data;
    data.makerFee = 1_000_001;
    _expectInvalidFee();
    zklighter.updateMarket(_updateSpotParams(2049, data));

    data.makerFee = 1;
    data.takerFee = 1_000_001;
    _expectInvalidFee();
    zklighter.updateMarket(_updateSpotParams(2049, data));
  }

  function test_updateSpotMarketRejectsInvalidMinAmounts() public {
    UpdateSpotData memory data;
    data.minBaseAmount = type(uint48).max;
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMinAmounts.selector);
    zklighter.updateMarket(_updateSpotParams(2049, data));

    data.minBaseAmount = 1;
    data.minQuoteAmount = type(uint48).max;
    _expectMarketRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidMarketLimits.selector);
    zklighter.updateMarket(_updateSpotParams(2049, data));
  }

  function _createPerpsParams(uint16 marketIndex, PerpsData memory data) internal pure returns (TxTypes.CreateMarket memory) {
    return TxTypes.CreateMarket({marketIndex: marketIndex, marketType: TxTypes.MarketType.Perps, marketData: _packPerps(data)});
  }

  function _createSpotParams(uint16 marketIndex, SpotData memory data) internal pure returns (TxTypes.CreateMarket memory) {
    return TxTypes.CreateMarket({marketIndex: marketIndex, marketType: TxTypes.MarketType.Spot, marketData: _packSpot(data)});
  }

  function _updatePerpsParams(uint16 marketIndex, uint8 status, PerpsData memory data) internal pure returns (TxTypes.UpdateMarket memory) {
    return TxTypes.UpdateMarket({marketIndex: marketIndex, marketType: TxTypes.MarketType.Perps, marketData: _packUpdatePerps(status, data)});
  }

  function _updateSpotParams(uint16 marketIndex, UpdateSpotData memory data) internal pure returns (TxTypes.UpdateMarket memory) {
    return TxTypes.UpdateMarket({marketIndex: marketIndex, marketType: TxTypes.MarketType.Spot, marketData: _packUpdateSpot(data)});
  }

  function _expectMarketRevert(bytes4 selector) internal {
    vm.expectRevert(selector);
  }

  function _expectInvalidFee() internal {
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidFeeAmount.selector);
  }

  function _expectInvalidAsset() internal {
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidAssetIndex.selector);
  }

  function _expectInvalidExtensionMultiplier() internal {
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_InvalidExtensionMultiplier.selector);
  }

  function _expectGenericMarketError() internal {
    vm.expectRevert(AdditionalZkLighter.AdditionalZkLighter_Error.selector);
  }
}
