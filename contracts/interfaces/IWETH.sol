// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IWETH is IERC20{
  function deposit() external payable;

  function withdraw(uint wad) external;
}