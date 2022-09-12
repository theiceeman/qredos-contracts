// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import "../models/Schema.sol";
import "../models/Events.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract QredosStore is Ownable, Schema, Events {
    using SafeERC20 for IERC20;

    // duration - APPROX. 90 days (3 months)
    // APR - 10% * 3 months (APR is 30)
    uint16 public constant downPaymentPercentage = 50; // borrowers will pay 50%

    // (borrowerAddress => PurchaseId[] => Details)
    mapping(address => mapping(uint256 => PurchaseDetails)) public Purchase;
    uint256 public totalPurchases = 0;
    // (borrower => purchaseId)
    mapping(address => uint256) countPurchaseForBorrower;
    // (id => Details)
    mapping(uint256 => LiquidationDetails) public Liquidation;
    uint256 public countLiquidation = 0;

    /////////////////////////
    ///   Internal   ////////
    /////////////////////////
    function getPurchaseByID(address borrowerAddress, uint256 purchaseId)
        external
        view
        returns (PurchaseDetails memory)
    {
        require(
            Purchase[borrowerAddress][purchaseId].isExists,
            "No such record"
        );
        return Purchase[borrowerAddress][purchaseId];
    }

    function getLiquidationByID(uint256 liquidationId)
        external
        view
        returns (LiquidationDetails memory)
    {
        require(Liquidation[liquidationId].isExists, "No such record");
        return Liquidation[liquidationId];
    }

    function _createPurchase(
        address borrowerAddress,
        uint256 loanId,
        uint256 poolId,
        address escrowAddress,
        address tokenAddress,
        uint256 tokenId
    ) external onlyOwner returns (uint256) {
        uint256 purchases = totalPurchases;
        Purchase[borrowerAddress][purchases] = PurchaseDetails(
            loanId,
            poolId,
            escrowAddress,
            tokenAddress,
            tokenId,
            PurchaseStatus.OPEN,
            true
        );
        ++totalPurchases;
        countPurchaseForBorrower[borrowerAddress] = ++countPurchaseForBorrower[
            borrowerAddress
        ];
        return purchases;
    }

    function _updatePurchase(
        address borrowerAddress,
        uint256 purchaseId,
        uint256 loanId,
        uint256 poolId,
        address escrowAddress,
        address tokenAddress,
        uint256 tokenId,
        PurchaseStatus status
    ) external onlyOwner {
        Purchase[borrowerAddress][purchaseId] = PurchaseDetails(
            loanId,
            poolId,
            escrowAddress,
            tokenAddress,
            tokenId,
            status,
            true
        );
    }

    function _createLiquidation(uint256 purchaseId, uint256 discountAmount)
        external
        onlyOwner
        returns (uint256)
    {
        uint256 liquidations = countLiquidation;
        Liquidation[liquidations] = LiquidationDetails(
            purchaseId,
            discountAmount,
            LiquidationStatus.OPEN,
            true
        );
        ++countLiquidation;
        return liquidations;
    }

    function _updateLiquidation(
        uint256 purchaseId,
        uint256 discountAmount,
        uint256 liquidationId,
        LiquidationStatus status
    ) external onlyOwner {
        Liquidation[liquidationId] = LiquidationDetails(
            purchaseId,
            discountAmount,
            status,
            true
        );
    }
}
