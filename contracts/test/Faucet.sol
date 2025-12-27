// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "../interfaces/IZkLighter.sol";

contract Faucet {
  IZkLighter public zkLighter;
  IGovernance public governance;
  IERC20 public usdc;
  address public minter;

  modifier onlyMinter() {
    require(msg.sender == minter);
    _;
  }

  constructor(address _zkLighter, address _governance, address _minter) {
    zkLighter = IZkLighter(_zkLighter);
    governance = IGovernance(_governance);
    minter = _minter;
    usdc = governance.usdc();
    usdc.approve(_zkLighter, type(uint256).max);
  }

  function mint(address[] memory _to, uint64[] memory _amount) public onlyMinter {
    uint256 length = _to.length;
    require(length == _amount.length);
    for (uint256 i = 0; i < length; i += 1) {
      zkLighter.deposit(_amount[i], _to[i]);
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
