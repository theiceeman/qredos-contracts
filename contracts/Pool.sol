// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import "./interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./interfaces/IMarket.sol";
import "./Markets.sol";

contract Pool{
  uint public totalDeposit;
  Markets markets;
  mapping(address => uint) public lenders;
  mapping(address => mapping(uint => uint)) borrowers;

  IWETH constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  IERC721 public immutable NFT; 

  event Deposit(address depositor, uint amount);
  event Borrow(address borrower, address market, uint id, uint amount);

  constructor(IERC721 _NFT){
    NFT = _NFT;
  }

  function deposit(uint amount) external payable {
    lenders[msg.sender] += amount;
    totalDeposit += amount;
    
    if(msg.value == 0){
      WETH.transferFrom(msg.sender, address(this), amount);
    }else{
      require(msg.value == amount, "Pool: Invalid Deposit");
    }

    emit Deposit(msg.sender, amount);
  }

  function borrow(uint amount, uint marketId, uint id) external payable {
    IMarket market = markets.getMarket(marketId);
    require(market.active(), "Pool: Market has been deactivated");
    market.buy(address(NFT), id);

    
    emit Borrow(msg.sender, address(market), id, amount);
  }

  function repay(uint amount) external payable {

  }
}