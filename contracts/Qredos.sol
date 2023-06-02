// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
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
        _poolRegistryStore.getPoolByID(poolId);
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
        /* 
            move funds to secure vault.
         */
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
            purchaseId,
            downPaymentAmount,
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
    ) external whenNotPaused {
        PurchaseDetails memory purchase = QredosStore(qredosStoreAddress)
            .getPurchaseByID(msg.sender, purchaseId);
        // check if payment has been paid previously
        if (repaymentType == LoanRepaymentType.FULL) {
            uint256 fullPayment = PoolRegistry(lendingPoolAddress)
                ._calcLoanFullPayment(purchase.loanId, poolId);
            IERC20(paymentTokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                fullPayment
            );
            IERC20(paymentTokenAddress).approve(
                lendingPoolAddress,
                fullPayment
            );
            uint256 loanRepaymentId = IPoolRegistry(lendingPoolAddress)
                .repayLoanFull(purchase.loanId, fullPayment, poolId);
            emit LoanRepaid(
                loanRepaymentId,
                purchase.loanId,
                fullPayment,
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
            IERC20(paymentTokenAddress).approve(
                lendingPoolAddress,
                partPayment
            );
            uint256 loanRepaymentId = IPoolRegistry(lendingPoolAddress)
                .repayLoanPart(purchase.loanId, partPayment, poolId);
            emit LoanRepaid(
                loanRepaymentId,
                purchase.loanId,
                partPayment,
                LoanRepaymentType.PART
            );
        }
    }

    function claimNft(
        uint256 purchaseId,
        uint256 poolId
    ) external whenNotPaused {
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
        uint256 currentNftPrice,
        address borrowerAddress
    ) external onlyOwner {
        QredosStore(qredosStoreAddress).getPurchaseByID(
            borrowerAddress,
            purchaseId
        );
        uint256 liquidationId = QredosStore(qredosStoreAddress)
            ._createLiquidation(purchaseId, discountAmount, currentNftPrice);
        emit StartLiquidation(purchaseId, discountAmount, liquidationId);
    }

    function completeLiquidation(
        uint256 liquidationId,
        address borrowerAddress
    ) external whenNotPaused {
        LiquidationDetails memory liquidation = QredosStore(qredosStoreAddress)
            .getLiquidationByID(liquidationId);
        PurchaseDetails memory purchase = QredosStore(qredosStoreAddress)
            .getPurchaseByID(borrowerAddress, liquidation.purchaseId);
        IERC20(paymentTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            liquidation.discountAmount
        );
        IERC20(paymentTokenAddress).safeTransfer(
            lendingPoolAddress,
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
            LiquidationStatus.COMPLETED,
            liquidation.currentNftPrice
        );
        QredosStore(qredosStoreAddress)._updatePurchase(
            borrowerAddress,
            liquidation.purchaseId,
            purchase.loanId,
            purchase.poolId,
            purchase.escrowAddress,
            purchase.tokenAddress,
            purchase.tokenId,
            PurchaseStatus.LIQUIDATED
        );
        emit CompleteLiquidation(
            liquidation.purchaseId,
            liquidationId,
            msg.sender
        );
    }

    function refundBorrower(
        uint256 purchaseId,
        uint256 liquidationId
    ) external whenNotPaused {
        PurchaseDetails memory purchase = QredosStore(qredosStoreAddress)
            .getPurchaseByID(msg.sender, purchaseId);
        require(
            purchase.status == PurchaseStatus.LIQUIDATED,
            "Qredos: cant refund borrower!"
        );
        uint256 refundAmount = _calcBorrowerRefundAmount(
            purchaseId,
            liquidationId
        );
        PoolRegistry(lendingPoolAddress)._completeRefundBorrower(
            msg.sender,
            refundAmount
        );
        emit RefundBorrower(purchaseId, msg.sender, refundAmount);
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

    function closePool(
        uint256 poolId,
        address reciever
    ) external whenNotPaused {
        PoolDetails memory Pool = PoolRegistryStore(
            PoolRegistry(lendingPoolAddress).poolRegistryStoreAddress()
        ).getPoolByID(poolId);
        require(msg.sender == Pool.creator, "caller should be pool creator!");
        uint256 amountWithdrawable = PoolRegistry(lendingPoolAddress)
            ._getPoolBalanceWithInterest(poolId);
        PoolRegistry(lendingPoolAddress).closePool(poolId, reciever);
        emit PoolClosed(poolId, amountWithdrawable);
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

    function _calcDownPayment(
        uint256 downPayment,
        uint256 principal
    ) internal view returns (bool) {
        uint16 rate = 100 /
            QredosStore(qredosStoreAddress).downPaymentPercentage();
        if (downPayment * rate == downPayment + principal) {
            return true;
        } else {
            return false;
        }
    }

    function _calcBorrowerRefundAmount(
        uint256 purchaseId,
        uint256 liquidationId
    ) public view returns (uint256) {
        // (DOWN PAYMENT + INSTALLMENTs PAID - DEFAULT FEE)

        PurchaseDetails memory Purchase = QredosStore(qredosStoreAddress)
            .getPurchaseByID(msg.sender, purchaseId);

        LoanDetails memory Loan = PoolRegistryStore(
            PoolRegistry(lendingPoolAddress).poolRegistryStoreAddress()
        ).getLoanByPoolID(Purchase.poolId, Purchase.loanId);

        PoolDetails memory Pool = PoolRegistryStore(
            PoolRegistry(lendingPoolAddress).poolRegistryStoreAddress()
        ).getPoolByID(Loan.poolId);

        LiquidationDetails memory Liquidation = QredosStore(qredosStoreAddress)
            .getLiquidationByID(liquidationId);

        uint256 downPayment = Loan.principal;
        uint256 partPayment = PoolRegistry(lendingPoolAddress)
            ._partPaymentWithoutDefault(Loan, Pool);

        // uint256 partPayment = PoolRegistry(lendingPoolAddress)
        //     ._calcLoanPartPayment(Purchase.loanId, Loan.poolId);

        uint256 countRepaymentsMade = PoolRegistryStore(
            PoolRegistry(lendingPoolAddress).poolRegistryStoreAddress()
        ).countLoanRepaymentsForLoan(Purchase.loanId);

        uint256 installmentPaid = partPayment * countRepaymentsMade;
        // uint256 defaultFeeAmount = (Loan.principal *
        //     PoolRegistry(lendingPoolAddress).DEFAULT_FEE_PERCENT()) / 100;

        uint256 defaultFeeAmount;
        if (
            PoolRegistry(lendingPoolAddress)._isLoanInDefault(
                Purchase.loanId,
                Purchase.poolId
            )
        ) {
            //  If user defaulted
            defaultFeeAmount =
                (Loan.principal *
                    PoolRegistry(lendingPoolAddress).DEFAULT_FEE_PERCENT()) /
                100;
        } else {
            // If user has not defaulted
            defaultFeeAmount = 0;
        }

        if (Liquidation.currentNftPrice < (Loan.principal * 2)) {
            uint256 nftPriceDifference = (Loan.principal * 2) -
                Liquidation.currentNftPrice;

            return
                (downPayment + installmentPaid) -
                (defaultFeeAmount + nftPriceDifference);
        } else {
            return (downPayment + installmentPaid) - defaultFeeAmount;
        }
    }

    /////////////////////////////
    ///   Utility Functions   ///
    ////////////////////////////

    function getPoolBalance(uint256 poolId) external view returns (uint256) {
        return PoolRegistry(lendingPoolAddress)._getPoolBalance(poolId);
    }
}
