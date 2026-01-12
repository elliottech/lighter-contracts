// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "../interfaces/IZkLighter.sol";

contract Faucet {
  IZkLighter public zkLighter;
  IERC20 public usdc;
  address public minter;
  mapping(uint16 => address) public assetIndexToAddress;

  modifier onlyMinter() {
    require(msg.sender == minter);
    _;
  }

  constructor(address _zkLighter, address _minter) {
    zkLighter = IZkLighter(_zkLighter);
    minter = _minter;
  }

  // receive ETH
  receive() external payable {}

  function approve(uint16 _assetIndex, address _erc20Address) public onlyMinter {
    IERC20(_erc20Address).approve(address(zkLighter), type(uint256).max);
    assetIndexToAddress[_assetIndex] = _erc20Address;
  }

  function mint(address[] memory _to, uint16[] memory _assetIndex, uint256[] memory _amount) public onlyMinter {
    uint256 length = _to.length;
    require(length == _amount.length);
    require(length == _assetIndex.length);
    for (uint256 i = 0; i < length; i += 1) {
      TxTypes.RouteType dest = TxTypes.RouteType.Spot;
      if (_assetIndex[i] == 3) {
        dest = TxTypes.RouteType.Perps;
      }
      if (_assetIndex[i] == 1) {
        zkLighter.deposit{value: _amount[i]}(_to[i], _assetIndex[i], dest, _amount[i]);
      } else {
        zkLighter.deposit(_to[i], _assetIndex[i], dest, _amount[i]);
      }
    }
  }

  // This is actually really useful for MM setup, as without this, we need to mint USDC on perp, wait for account to be created,
  // create a TMP api key and wait for it to be processed, and transfer the funds from perp to spot.
  // Code duplication is not an issue as this is internal only.
  // Kept the past method for backwards compatibility.
  function mintWithRoute(
    address[] memory _to,
    uint16[] memory _assetIndex,
    uint256[] memory _amount,
    TxTypes.RouteType[] memory _route
  ) public onlyMinter {
    uint256 length = _to.length;
    require(length == _amount.length);
    require(length == _assetIndex.length);
    for (uint256 i = 0; i < length; i += 1) {
      TxTypes.RouteType dest = _route[i];
      if (_assetIndex[i] == 1) {
        zkLighter.deposit{value: _amount[i]}(_to[i], _assetIndex[i], dest, _amount[i]);
      } else {
        zkLighter.deposit(_to[i], _assetIndex[i], dest, _amount[i]);
      }
    }
  }

  function transfer(address[] memory _to, uint16[] memory _assetIndex, uint256[] memory _amount) public onlyMinter {
    uint256 length = _to.length;
    require(length == _amount.length);
    require(length == _assetIndex.length);
    for (uint256 i = 0; i < length; i += 1) {
      if (_assetIndex[i] == 1) {
        payable(_to[i]).transfer(_amount[i]);
      } else {
        IERC20(assetIndexToAddress[_assetIndex[i]]).transfer(_to[i], _amount[i]);
      }
    }
  }

  function withdraw(address tokenAddress, uint256 amount) external onlyMinter {
    IERC20 token = IERC20(tokenAddress);
    // special value to give me the maximum
    if (amount == 0) {
      amount = token.balanceOf(address(this));
    }
    require(token.transfer(minter, amount), "Token transfer failed");
  }
}
