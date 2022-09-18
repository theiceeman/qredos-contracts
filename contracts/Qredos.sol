// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import "hardhat/console.sol";
import "./models/Schema.sol";
import "./models/Events.sol";

import "./interfaces/IPoolRegistry.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./PoolRegistry.sol";
import "./Escrow.sol";
import "./store/PoolRegistryStore.sol";
import "./store/QredosStore.sol";

contract Qredos is Ownable, Schema, Events, IERC721Receiver {
    using SafeERC20 for IERC20;

    address public paymentTokenAddress;
    address public lendingPoolAddress;

    address public qredosStoreAddress;
    bool public isPaused;

    modifier whenNotPaused() {
        require(!isPaused, "Qredos: currently paused!");
        _;
    }

    constructor(
        address _paymentTokenAddress,
        address _lendingPoolAddress,
        address _QredosStoreAddress
    ) {
        paymentTokenAddress = _paymentTokenAddress;
        lendingPoolAddress = _lendingPoolAddress;

        qredosStoreAddress = _QredosStoreAddress;

        emit QredosContractDeployed(_paymentTokenAddress, _lendingPoolAddress);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function purchaseNFT(
        address tokenAddress,
        uint256 tokenId,
        uint256 downPaymentAmount,
        uint256 principal,
        uint256 poolId
    ) external whenNotPaused {
        require(
            tokenAddress != address(0x0),
            "Qredos.purchaseNFT: address is zero address!"
        );
        PoolRegistryStore _poolRegistryStore = PoolRegistryStore(
            PoolRegistry(lendingPoolAddress).poolRegistryStoreAddress()
        );
        PoolDetails memory Pool = _poolRegistryStore.getPoolByID(poolId);
        require(
            _calcDownPayment(downPaymentAmount, principal),
            "Qredos.purchaseNFT: Invalid principal!"
        );
        require(
            PoolRegistry(lendingPoolAddress)._getPoolBalance(poolId) >
                principal,
            "Qredos.purchaseNFT: Selected pool can't fund purchase!"
        );
        IERC20(paymentTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            downPaymentAmount
        );
        uint256 loanId = IPoolRegistry(lendingPoolAddress).requestLoan(
            principal,
            poolId,
            msg.sender
        );

        require(
            IERC20(paymentTokenAddress).balanceOf(address(this)) >=
                (downPaymentAmount + principal),
            "Qredos.purchaseNFT: Insufficient funds!"
        );
        uint256 purchaseId = QredosStore(qredosStoreAddress)._createPurchase(
            msg.sender,
            loanId,
            poolId,
            address(0x0),
            tokenAddress,
            tokenId
        );

        emit PurchaseCreated(
            msg.sender,
            poolId,
            loanId,
            purchaseId,
            tokenId,
            tokenAddress,
            downPaymentAmount,
            principal,
            Pool.APR,
            Pool.durationInSecs,
            QredosStore(qredosStoreAddress).downPaymentPercentage()
        );
    }

    function completeNFTPurchase(uint256 purchaseId) external whenNotPaused {
        PurchaseDetails memory purchase = QredosStore(qredosStoreAddress)
            .getPurchaseByID(msg.sender, purchaseId);
        require(
            ERC721(purchase.tokenAddress).ownerOf(purchase.tokenId) ==
                address(this),
            "Qredos: Purchase Incomplete!"
        );

        // update to proxy pattern to make deployment cheaper
        address escrowAddress = address(
            new Escrow(address(this), purchase.tokenId, purchase.tokenAddress)
        );
        require(
            Escrow(escrowAddress).owner() == address(this),
            "Qredos: Invalid escrow owner!"
        );
        ERC721(purchase.tokenAddress).approve(escrowAddress, purchase.tokenId);
        Escrow(escrowAddress).deposit(purchase.tokenId, purchase.tokenAddress);

        QredosStore(qredosStoreAddress)._updatePurchase(
            msg.sender,
            purchaseId,
            purchase.loanId,
            purchase.poolId,
            escrowAddress,
            purchase.tokenAddress,
            purchase.tokenId,
            PurchaseStatus.COMPLETED
        );
        emit PurchaseCompleted(purchaseId);
    }

    function repayLoan(
        uint256 purchaseId,
        LoanRepaymentType repaymentType,
        uint256 poolId
    ) external whenNotPaused  {
        PurchaseDetails memory purchase = QredosStore(qredosStoreAddress)
            .getPurchaseByID(msg.sender, purchaseId);
        LoanDetails memory loan = PoolRegistryStore(
            PoolRegistry(lendingPoolAddress).poolRegistryStoreAddress()
        ).getLoanByPoolID(poolId, purchase.loanId);
        // check if payment has been paid previously
        if (repaymentType == LoanRepaymentType.FULL) {
            IERC20(paymentTokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                loan.principal
            );
            IERC20(paymentTokenAddress).approve(lendingPoolAddress, loan.principal);
            uint256 loanRepaymentId = IPoolRegistry(lendingPoolAddress)
                .repayLoanFull(purchase.loanId, loan.principal, poolId);
            emit LoanRepaid(
                loanRepaymentId,
                purchase.loanId,
                loan.principal,
                LoanRepaymentType.FULL
            );
        } else if (repaymentType == LoanRepaymentType.PART) {
            uint256 partPayment = PoolRegistry(lendingPoolAddress)
                ._calcLoanPartPayment(purchase.loanId, poolId);
            IERC20(paymentTokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                partPayment
            );
            IERC20(paymentTokenAddress).approve(lendingPoolAddress, loan.principal);
            uint256 loanRepaymentId = IPoolRegistry(lendingPoolAddress)
                .repayLoanPart(purchase.loanId, partPayment, poolId);
            emit LoanRepaid(
                loanRepaymentId,
                purchase.loanId,
                loan.principal,
                LoanRepaymentType.PART
            );
        }
    }

    function claimNft(uint256 purchaseId, uint256 poolId)
        external
        whenNotPaused
    {
        PurchaseDetails memory purchase = QredosStore(qredosStoreAddress)
            .getPurchaseByID(msg.sender, purchaseId);
        LoanDetails memory loan = PoolRegistryStore(
            PoolRegistry(lendingPoolAddress).poolRegistryStoreAddress()
        ).getLoanByPoolID(poolId, purchase.loanId);
        require(
            loan.status == LoanStatus.CLOSED,
            "Qredos: loanRepayment incomplete!"
        );
        require(
            Escrow(purchase.escrowAddress).claim(msg.sender),
            "Qredos: claim reverted!"
        );
        emit NFTClaimed(purchaseId, msg.sender);
    }

    function startLiquidation(
        uint256 purchaseId,
        uint256 discountAmount,
        address borrowerAddress
    ) external onlyOwner {
        PurchaseDetails memory purchase = QredosStore(qredosStoreAddress)
            .getPurchaseByID(borrowerAddress, purchaseId);
        require(
            PoolRegistry(lendingPoolAddress)._isLoanInDefault(
                purchase.loanId,
                purchase.poolId
            ) != false,
            "Qredos.startLiquidation: loan is not defaulted!"
        );
        uint256 liquidationId = QredosStore(qredosStoreAddress)
            ._createLiquidation(purchaseId, discountAmount);
        emit StartLiquidation(purchaseId, discountAmount, liquidationId);
    }

    function completeLiquidation(uint256 liquidationId, address borrowerAddress)
        external
        whenNotPaused
    {
        LiquidationDetails memory liquidation = QredosStore(qredosStoreAddress)
            .getLiquidationByID(liquidationId);
        PurchaseDetails memory purchase = QredosStore(qredosStoreAddress)
            .getPurchaseByID(borrowerAddress, liquidation.purchaseId);
        IERC20(paymentTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            liquidation.discountAmount
        );
        require(
            Escrow(purchase.escrowAddress).claim(msg.sender),
            "Qredos: liquidation reverted!"
        );
        QredosStore(qredosStoreAddress)._updateLiquidation(
            liquidation.purchaseId,
            liquidation.discountAmount,
            liquidationId,
            LiquidationStatus.COMPLETED
        );
        emit CompleteLiquidation(
            liquidation.purchaseId,
            liquidationId,
            msg.sender
        );
    }

    function createPool(
        uint256 _amount,
        uint16 _paymentCycle,
        uint16 _APR,
        uint256 _durationInSecs,
        uint16 _durationInMonths,
        address _creator
    ) external whenNotPaused {
        IERC20(paymentTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        IERC20(paymentTokenAddress).approve(lendingPoolAddress, _amount);
        PoolRegistry(lendingPoolAddress).createPool(
            _amount,
            _paymentCycle,
            _APR,
            _durationInSecs,
            _durationInMonths,
            _creator
        );
    }

    function fundPool(uint256 poolId, uint256 amount) external whenNotPaused {
        IERC20(paymentTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        IERC20(paymentTokenAddress).approve(lendingPoolAddress, amount);
        PoolRegistry(lendingPoolAddress).fundPool(poolId, amount);
    }

    function closePool(uint256 poolId, address reciever)
        external
        whenNotPaused
    {
        PoolRegistry(lendingPoolAddress).closePool(poolId, reciever);
    }

    /////////////////////////
    ///   Admin Actions   ///
    /////////////////////////

    /**
     * @notice Toggling the pause flag
     * @dev Only owner
     */
    function toggleIsPaused() external onlyOwner {
        isPaused = !isPaused;
    }

    function forwardAllFunds() external onlyOwner {
        IERC20(paymentTokenAddress).transfer(
            owner(),
            IERC20(paymentTokenAddress).balanceOf(address(this))
        );
    }

    function _calcDownPayment(uint256 downPayment, uint256 principal)
        internal
        view
        returns (bool)
    {
        uint16 rate = 100 /
            QredosStore(qredosStoreAddress).downPaymentPercentage();
        if (downPayment * rate == downPayment + principal) {
            return true;
        } else {
            return false;
        }
    }

    /////////////////////////////
    ///   Utility Functions   ///
    ////////////////////////////

    function getPoolBalance(uint256 poolId) external view returns (uint256) {
        return PoolRegistry(lendingPoolAddress)._getPoolBalance(poolId);
    }
}
