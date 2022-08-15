// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import "../interfaces/IMarket.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Opensea is IMarket, Ownable {
  uint public version;
  string public name;
  address public marketAddress;
  bool public constant override isKredos = true;
  bool public override active = true;

  event Buy(address token, uint id);
  event Activate(address owner);
  event Deactivate(address owner);

  constructor(uint8 _version, address _marketAddress, string memory _name){
    version = _version;
    marketAddress = _marketAddress;
    name = _name;
  }

  function buy(address token, uint id) override external{
    
    emit Buy(token, id);
  } 

  function deactivate() override external onlyOwner{
    active = false;
    Deactivate(msg.sender);
  }

  function activate() external onlyOwner{
    active = true;
    Activate(msg.sender);
  }

}
