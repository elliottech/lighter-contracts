// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OwnableERC20 is ERC20 {
  address public owner;
  uint8 private _decimals;

  constructor(string memory _name, string memory _symbol, uint8 __decimals) ERC20(_name, _symbol) {
    owner = msg.sender;
    _decimals = __decimals;
  }

  function mint(address _to, uint256 amount) external {
    require(msg.sender == owner);
    _mint(_to, amount);
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }
}
