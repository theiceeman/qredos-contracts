// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import "./models/Schema.sol";
import "./models/Events.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./store/PoolRegistryStore.sol";
import "hardhat/console.sol";

contract PoolRegistry is Ownable, Schema, Events, PoolRegistryStore {
    using SafeERC20 for IERC20;

    IERC20 internal lendingToken;
    address public poolRegistryStoreAddress;
    uint256 constant DEFAULT_FEE_PERCENT = 15; // default fee percentage

    constructor(address _lendingTokenAddress, address _PoolRegistryStoreAddress)
    {
        lendingToken = IERC20(_lendingTokenAddress);
        poolRegistryStoreAddress = _PoolRegistryStoreAddress;
        emit PoolRegistryContractDeployed();
    }

    function createPool(
        uint256 _amount,
        uint16 _paymentCycle,
        uint16 _APR,
        uint256 _durationInSecs,
        uint16 _durationInMonths,
        address _creator
    ) external onlyOwner {
        require(
            _paymentCycle != 0 &&
                _durationInSecs != 0 &&
                _durationInMonths != 0 &&
                _amount != 0 &&
                _APR != 0,
            "Pool.createPool: Invalid Input!"
        );
        require(_creator != address(0x0), "Pool.createPool: Invalid address!");
        lendingToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 poolId = PoolRegistryStore(poolRegistryStoreAddress)
            ._createPool(
                _amount,
                _paymentCycle,
                _APR,
                _durationInSecs,
                _durationInMonths,
                _creator
            );
        emit PoolCreated(poolId, _creator);
        emit PoolFunded(poolId, _amount);
    }

    // Get pools that can cover principal
    function getValidPools(uint256 principal)
        external
        view
        onlyOwner
        returns (uint256[] memory)
    {
        require(principal > 0, "Pool.getValidPools: Invalid input!");
        uint256[] memory validPools;
        uint256 count = 0;
        uint256 totalPools = PoolRegistryStore(poolRegistryStoreAddress)
            .totalPools();
        for (uint256 i = 0; i < totalPools; i++) {
            if (
                PoolRegistryStore(poolRegistryStoreAddress)
                    .getPoolByID(i)
                    .amount > principal
            ) {
                validPools[count] = i;
                count++;
            }
        }
        return validPools;
    }

    function requestLoan(
        uint256 principal,
        uint256 poolId,
        address borrower
    ) external onlyOwner returns (uint256) {
        PoolDetails memory Pool = PoolRegistryStore(poolRegistryStoreAddress)
            .getPoolByID(poolId);
        require(
            Pool.status == PoolStatus.OPEN,
            "Pool.requestLoan: Pool status closed!"
        );
        require(principal > 0, "Pool.requestLoan: Invalid input!");
        require(
            borrower != address(0x0),
            "Pool.requestLoan: Invalid borrower!"
        );
        lendingToken.safeTransfer(msg.sender, principal);
        uint256 loanId = PoolRegistryStore(poolRegistryStoreAddress)
            ._createLoan(poolId, borrower, principal);
        emit LoanCreated(loanId, borrower, principal);
        return loanId;
    }

    function repayLoanFull(
        uint256 loanId,
        uint256 amount,
        uint256 poolId
    ) external onlyOwner returns (uint256) {
        LoanDetails memory Loan = PoolRegistryStore(poolRegistryStoreAddress)
            .getLoanByPoolID(poolId, loanId);
        require(amount > 0, "Pool.repayLoanFull: Invalid input!");
        // Amount should equal full amount borrowed.
        require(
            amount == Loan.principal,
            "Pool.repayLoanFull: Invalid amount!"
        );
        lendingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 loanRepaymentId = PoolRegistryStore(poolRegistryStoreAddress)
            ._createLoanRepayment(loanId, amount, LoanRepaymentType.FULL);
        PoolRegistryStore(poolRegistryStoreAddress)._updateLoan(
            loanId,
            poolId,
            Loan.borrower,
            Loan.principal,
            Loan.createdAtTimestamp,
            LoanStatus.CLOSED
        );
        return loanRepaymentId;
    }

    function repayLoanPart(
        uint256 loanId,
        uint256 amount,
        uint256 poolId
    ) external onlyOwner returns (uint256) {
        LoanDetails memory Loan = PoolRegistryStore(poolRegistryStoreAddress)
            .getLoanByPoolID(poolId, loanId);
        require(amount > 0, "Pool.repayLoanPart: Invalid input!");
        // amount should equal percentage scheduled for one payment cycle
        require(
            amount == _calcLoanPartPayment(loanId, poolId),
            "Pool.repayLoanPart: Invalid amount!"
        );
        lendingToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 loanRepaymentId = PoolRegistryStore(poolRegistryStoreAddress)
            ._createLoanRepayment(loanId, amount, LoanRepaymentType.PART);
        // check if loan payment is complete; then set status to close.
        PoolDetails memory Pool = PoolRegistryStore(poolRegistryStoreAddress)
            .getPoolByID(poolId);
        if (
            PoolRegistryStore(poolRegistryStoreAddress)
                .countLoanRepaymentsForLoan(loanId) == Pool.paymentCycle
        ) {
            PoolRegistryStore(poolRegistryStoreAddress)._updateLoan(
                loanId,
                poolId,
                Loan.borrower,
                Loan.principal,
                Loan.createdAtTimestamp,
                LoanStatus.CLOSED
            );
        }
        return loanRepaymentId;
    }

    function fundPool(uint256 poolId, uint256 amount) external onlyOwner {
        PoolDetails memory Pool = PoolRegistryStore(poolRegistryStoreAddress)
            .getPoolByID(poolId);
        require(
            Pool.status == PoolStatus.OPEN,
            "Pool.fundPool: Pool is closed!"
        );
        require(amount > 0, "Pool: Invalid input!");
        lendingToken.safeTransferFrom(msg.sender, address(this), amount);
        PoolRegistryStore(poolRegistryStoreAddress)._updatePool(
            poolId,
            Pool.amount + amount,
            Pool.paymentCycle,
            Pool.APR,
            Pool.durationInSecs,
            Pool.durationInMonths,
            Pool.creator,
            Pool.status
        );
        emit PoolFunded(poolId, amount);
    }

    function closePool(uint256 poolId, address reciever) external onlyOwner {
        PoolDetails memory Pool = PoolRegistryStore(poolRegistryStoreAddress)
            .getPoolByID(poolId);
        uint256 amountWithdrawable = _getPoolBalanceWithInterest(poolId);
        PoolRegistryStore(poolRegistryStoreAddress)._updatePool(
            poolId,
            Pool.amount,
            Pool.paymentCycle,
            Pool.APR,
            Pool.durationInSecs,
            Pool.durationInMonths,
            Pool.creator,
            PoolStatus.CLOSED
        );
        lendingToken.safeTransfer(reciever, amountWithdrawable);
    }

    // INTERNAL FUNCTIONS

    // (pool balance - total lent out) + total repaid
    // This can be used to check exact amount pool creator can currently withdraw
    function _getPoolBalanceWithInterest(uint256 poolId)
        public
        view
        returns (uint256)
    {
        uint256 totalAmountLoaned;
        uint256 totalAmountRepaid;
        for (uint256 i = 0; i < countLoansInPool[poolId]; i++) {
            LoanDetails memory Loan = PoolRegistryStore(
                poolRegistryStoreAddress
            ).getLoanByPoolID(poolId, i);
            totalAmountLoaned += Loan.principal;
            for (uint256 j = 0; j < countLoanRepaymentsForLoan[i]; j++) {
                LoanRepaymentDetails memory LoanRepayment = PoolRegistryStore(
                    poolRegistryStoreAddress
                )._getLoanRepaymentByLoanID(i, j);
                totalAmountRepaid += LoanRepayment.amount;
            }
        }
        return
            (PoolRegistryStore(poolRegistryStoreAddress)
                .getPoolByID(poolId)
                .amount - totalAmountLoaned) + totalAmountRepaid;
    }

    // (pool balance - total lent out)
    // This can be used to check exact amount that can be withdrawn from a pool
    function _getPoolBalance(uint256 poolId) public view returns (uint256) {
        uint256 totalAmountLoaned;
        uint256 loansInPool = PoolRegistryStore(poolRegistryStoreAddress)
            .getCountLoansInPool(poolId);
        for (uint256 i = 0; i < loansInPool; i++) {
            totalAmountLoaned += PoolRegistryStore(poolRegistryStoreAddress)
                .getLoanByPoolID(poolId, i)
                .principal;
        }
        return (PoolRegistryStore(poolRegistryStoreAddress)
            .getPoolByID(poolId)
            .amount - totalAmountLoaned);
    }

    function _calcLoanPartPayment(uint256 loanId, uint256 poolId)
        public
        view
        returns (uint256)
    {
        LoanDetails memory Loan = PoolRegistryStore(poolRegistryStoreAddress)
            .getLoanByPoolID(poolId, loanId);

        PoolDetails memory Pool = PoolRegistryStore(poolRegistryStoreAddress)
            .getPoolByID(poolId);

        if (_isLoanInDefault(loanId, poolId)) {
            //  If user defaulted
            return _partPaymentWithDefault(Loan, Pool);
        } else {
            // If user has not defaulted
            return _partPaymentWithoutDefault(Loan, Pool);
        }
    }

    function _partPaymentWithoutDefault(
        LoanDetails memory Loan,
        PoolDetails memory Pool
    ) internal pure returns (uint256) {
        uint256 interest = (Loan.principal * Pool.APR) / 100;
        return (Loan.principal + interest) / Pool.paymentCycle;
    }

    function _partPaymentWithDefault(
        LoanDetails memory Loan,
        PoolDetails memory Pool
    ) internal pure returns (uint256) {
        uint256 partPayment = Loan.principal / Pool.paymentCycle;
        uint256 defaultFeeAmount = (Loan.principal * DEFAULT_FEE_PERCENT) / 100;
        uint256 interest = (Loan.principal * Pool.APR) / 100;
        return partPayment + interest + defaultFeeAmount;
    }

    function _calcLoanFullPayment(uint256 loanId, uint256 poolId)
        public
        view
        returns (uint256)
    {
        LoanDetails memory Loan = PoolRegistryStore(poolRegistryStoreAddress)
            .getLoanByPoolID(poolId, loanId);

        PoolDetails memory Pool = PoolRegistryStore(poolRegistryStoreAddress)
            .getPoolByID(poolId);

        // If user has not defaulted
        if (block.timestamp < (Loan.createdAtTimestamp + Pool.durationInSecs)) {
            return Loan.principal;
        } else {
            //  If user defaulted
            return _fullPaymentWithDefault(Loan);
        }
    }

    function _fullPaymentWithDefault(LoanDetails memory Loan)
        internal
        pure
        returns (uint256)
    {
        uint256 defaultFeeAmount = (Loan.principal * DEFAULT_FEE_PERCENT) / 100;
        return Loan.principal + defaultFeeAmount;
    }

    function _isLoanInDefault(uint256 loanId, uint256 poolId)
        public
        view
        returns (bool)
    {
        PoolDetails memory Pool = PoolRegistryStore(poolRegistryStoreAddress)
            .getPoolByID(poolId);
        // check if loanId is valid
        LoanDetails memory Loan = PoolRegistryStore(poolRegistryStoreAddress)
            .getLoanByPoolID(poolId, loanId);

        uint256 poolPaymentCycle = Pool.paymentCycle;
        uint256 countPartPayment;
        for (uint256 i = 0; i <= poolPaymentCycle; i++) {
            LoanRepaymentDetails memory LoanRepayment = PoolRegistryStore(
                poolRegistryStoreAddress
            )._getLoanRepaymentByLoanID(loanId, i);

            if (LoanRepayment.isExists == true) {
                if (LoanRepayment.RepaymentType == LoanRepaymentType.FULL) {
                    return false;
                } else if (
                    LoanRepayment.RepaymentType == LoanRepaymentType.PART
                ) {
                    countPartPayment++;
                }
            } else {
                uint256 partPayDuration = Pool.durationInSecs /
                    Pool.paymentCycle;
                uint256 partPayDeadline = Loan.createdAtTimestamp +
                    (partPayDuration * (i + 1));
                if (block.timestamp > partPayDeadline) {
                    return true;
                } else {
                    return false;
                }
            }
        }
        if (poolPaymentCycle == countPartPayment) {
            return false;
        }
        return true;
    }
}
