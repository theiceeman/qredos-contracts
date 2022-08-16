// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract Escrow is IERC721Receiver {

  enum EscrowStatus {NFT_DEPOSITED, NFT_WITHDRAWN}

    address public owner;
    address public immutable borrowerAddress;
    uint256 public immutable tokenId;
    address public immutable tokenAddress;
    EscrowStatus public status;

    constructor(
        address _borrowerAddress,
        uint256 _tokenId,
        address _tokenAddress
    ) {
        owner = msg.sender;
        borrowerAddress = _borrowerAddress;
        tokenId = _tokenId;
        tokenAddress = _tokenAddress;
    }


    function deposit(uint256 tokenId, address tokenAddress) external onlyOwner returns(bool){
       require(tokenAddress !== 0, "Escrow: address is zero address!");
       require(
        ERC721(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenId),
        "Escrow: Transfer failed!")
       status = EscrowStatus.NFT_DEPOSITED;
       return true;

    }

    function withdraw(address newNftOwnerAddress) external onlyOwner {
       require(newNftOwnerAddress !== 0, "Escrow: address is zero address!");
       require(
        ERC721(tokenAddress).safeTransferFrom(address(this), newNftOwnerAddress, tokenId),
        "Escrow: Transfer failed!")
       status = EscrowStatus.NFT_WITHDRAWN;
       return true;

    }


    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not owner");
        _;
    }
}
