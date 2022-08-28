// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import "./models/Schema.sol";
import "./models/Events.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./store/PoolRegistryStore.sol";

contract PoolRegistry is Ownable, Schema, Events, PoolRegistryStore {
    using SafeERC20 for IERC20;

    constructor(address _lendingTokenAddress) {
        lendingToken = IERC20(_lendingTokenAddress);
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
        uint256 poolId = _createPool(
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
        for (uint256 i = 0; i < totalPools; i++) {
            if (Pools[i].amount > principal) {
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
        require(Pools[poolId].isExists, "Pool.requestLoan: Invalid pool Id!");
        require(
            Pools[poolId].status == PoolStatus.OPEN,
            "Pool.requestLoan: Pool status closed!"
        );
        require(principal > 0, "Pool.requestLoan: Invalid input!");
        require(
            borrower != address(0x0),
            "Pool.requestLoan: Invalid borrower!"
        );
        lendingToken.safeTransferFrom(address(this), msg.sender, principal);
        uint256 loanId = _createLoan(poolId, borrower, principal);
        emit LoanCreated(loanId, borrower, principal);
        return loanId;
    }

    function repayLoanFull(
        uint256 loanId,
        uint256 amount,
        uint256 poolId
    ) external onlyOwner {
        require(
            Loans[poolId][loanId].isExists,
            "Pool.repayLoanFull: Invalid loan Id!"
        );
        require(amount > 0, "Pool.repayLoanFull: Invalid input!");
        // Amount should equal full amount borrowed.
        require(
            amount == Loans[poolId][loanId].principal,
            "Pool.repayLoanFull: Invalid amount!"
        );
        lendingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 loanRepaymentId = _createLoanRepayment(loanId, amount);
        Loans[poolId][loanId].status = LoanStatus.CLOSED;
        emit LoanRepaid(
            loanRepaymentId,
            loanId,
            amount,
            LoanRepaymentType.FULL
        );
    }

    function repayLoanPart(
        uint256 loanId,
        uint256 amount,
        uint256 poolId
    ) external onlyOwner {
        require(
            Loans[poolId][loanId].isExists,
            "Pool.repayLoanPart: Invalid loan Id!"
        );
        require(amount > 0, "Pool.repayLoanPart: Invalid input!");
        // amount should equal percentage scheduled for one payment cycle
        require(
            amount == _calcLoanPartPayment(loanId, poolId),
            "Pool.repayLoanPart: Invalid amount!"
        );
        lendingToken.safeTransferFrom(msg.sender, address(this), amount);
        /*
            check and set loan status to closed
        */
        uint256 loanRepaymentId = _createLoanRepayment(loanId, amount);
        emit LoanRepaid(
            loanRepaymentId,
            loanId,
            amount,
            LoanRepaymentType.PART
        );
    }

    function fundPool(uint256 poolId, uint256 amount) external onlyOwner {
        require(Pools[poolId].isExists, "Pool.fundPool: Invalid pool Id!");
        require(
            Pools[poolId].status == PoolStatus.OPEN,
            "Pool.fundPool: Pool is closed!"
        );
        require(amount > 0, "Pool: Invalid input!");
        lendingToken.safeTransferFrom(msg.sender, address(this), amount);
        _updatePool(
            poolId,
            Pools[poolId].amount + amount,
            Pools[poolId].paymentCycle,
            Pools[poolId].APR,
            Pools[poolId].durationInSecs,
            Pools[poolId].durationInMonths,
            Pools[poolId].creator,
            Pools[poolId].status
        );
        emit PoolFunded(poolId, amount);
    }

    function closePool(uint256 poolId, address reciever) external onlyOwner {
        require(Pools[poolId].isExists, "Pool: Invalid pool Id!");
        uint256 amountWithdrawable = _getPoolBalanceWithInterest(poolId);
        _updatePool(
            poolId,
            Pools[poolId].amount,
            Pools[poolId].paymentCycle,
            Pools[poolId].APR,
            Pools[poolId].durationInSecs,
            Pools[poolId].durationInMonths,
            Pools[poolId].creator,
            PoolStatus.CLOSED
        );
        lendingToken.safeTransferFrom(
            address(this),
            reciever,
            amountWithdrawable
        );
        emit PoolClosed(poolId, amountWithdrawable);
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
            totalAmountLoaned += Loans[poolId][i].principal;
            for (uint256 j = 0; j < countLoanRepaymentsForLoan[i]; j++) {
                totalAmountRepaid += LoanRepayment[i][j].amount;
            }
        }
        return (Pools[poolId].amount - totalAmountLoaned) + totalAmountRepaid;
    }

    // (pool balance - total lent out)
    // This can be used to check exact amount that can be withdrawn from a pool
    function _getPoolBalance(uint256 poolId) public view returns (uint256) {
        uint256 totalAmountLoaned;
        for (uint256 i = 0; i < countLoansInPool[poolId]; i++) {
            totalAmountLoaned += Loans[poolId][i].principal;
        }
        return (Pools[poolId].amount - totalAmountLoaned);
    }

    function _calcLoanPartPayment(uint256 loanId, uint256 poolId)
        public
        view
        returns (uint256)
    {
        return
            Loans[poolId][loanId].principal /
            Pools[Loans[poolId][loanId].principal].paymentCycle;
    }
}
