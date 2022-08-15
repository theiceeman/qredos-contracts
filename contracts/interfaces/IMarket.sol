// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

interface IMarket {
  function active() external returns(bool);
  function isKredos() external returns(bool);
  function deactivate() external;
  function buy (address token, uint id) external;
  
  // function auction (address token, uint id) external;

  // function sell (address token, uint id) external;
}