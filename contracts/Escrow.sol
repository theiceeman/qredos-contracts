// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

import "./interfaces/IPool.sol";

contract Escrow {
  // Pool the Escrow is associated with
  IPool public pool;

  constructor(IPool _pool){
    pool = _pool;
  }


  // store an NFT
  function deposit() external{

  }

  // remove an NFT from the contract
  function withdraw() external{

  }
}
