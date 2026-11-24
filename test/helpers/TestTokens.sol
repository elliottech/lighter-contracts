// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract NoMetadataToken {
  mapping(address => uint256) public balanceOf;
  mapping(address => mapping(address => uint256)) public allowance;

  function transfer(address to, uint256 amount) external returns (bool) {
    balanceOf[msg.sender] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    allowance[from][msg.sender] -= amount;
    balanceOf[from] -= amount;
    balanceOf[to] += amount;
    return true;
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    allowance[msg.sender][spender] = amount;
    return true;
  }

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }
}

contract SimpleERC20 is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {
    _mint(msg.sender, 1_000_000e18);
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

/// @dev Credits the recipient `bonus` extra units on every transfer (recipient receives more than requested).
contract ExcessTransferToken is ERC20 {
  uint256 public immutable bonus;

  constructor(uint256 _bonus) ERC20("Excess", "EXC") {
    bonus = _bonus;
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function _transfer(address from, address to, uint256 amount) internal override {
    super._transfer(from, to, amount);
    _mint(to, bonus);
  }
}

/// @dev Burns `fee` units from the recipient on every transfer (recipient receives less than requested).
contract FeeOnTransferToken is ERC20 {
  uint256 public immutable fee;

  constructor(uint256 _fee) ERC20("Fee", "FEE") {
    fee = _fee;
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function _transfer(address from, address to, uint256 amount) internal override {
    super._transfer(from, to, amount);
    _burn(to, fee);
  }
}

contract SimpleERC20Permit is ERC20, ERC20Permit {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}
