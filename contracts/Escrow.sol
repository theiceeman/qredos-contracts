// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract Escrow is IERC721Receiver {
    enum EscrowStatus {
        NFT_DEPOSITED,
        NFT_WITHDRAWN
    }

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

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function deposit(uint256 _tokenId, address _tokenAddress)
        external
        onlyOwner
        returns (bool)
    {
        require(
            _tokenAddress != address(0x0),
            "Escrow: address is zero address!"
        );
        ERC721(_tokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _tokenId
        );
        status = EscrowStatus.NFT_DEPOSITED;
        return true;
    }

    function claim(address newNftOwnerAddress)
        external
        onlyOwner
        returns (bool)
    {
        require(
            newNftOwnerAddress != address(0x0),
            "Escrow: address is zero address!"
        );
        ERC721(tokenAddress).safeTransferFrom(
            address(this),
            newNftOwnerAddress,
            tokenId
        );
        status = EscrowStatus.NFT_WITHDRAWN;
        return true;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: caller is not owner");
        _;
    }
}
