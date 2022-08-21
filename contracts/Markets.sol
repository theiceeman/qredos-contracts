// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IMarket.sol";

contract Markets is Ownable{

  IMarket[] public markets;

  event MarketAdded(address market);

  function addMarket(IMarket market) public onlyOwner{
    require(market.isKredos() && market.active(), "Markets: Invalid market");
    markets[markets.length] = market;
    emit MarketAdded(address(market));
  }

  function getMarket(uint id) external view returns(IMarket){
    require(id < markets.length, "Markets: Invalid Market");
    IMarket market = markets[id];
    return market;
  }
} 