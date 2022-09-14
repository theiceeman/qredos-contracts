// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import "../models/Schema.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract PoolRegistryStore is Ownable, Schema {
    using SafeERC20 for IERC20;

    mapping(uint256 => PoolDetails) public Pools;
    uint256 public totalPools = 0;

    // (poolId => loanId[] => Details)
    mapping(uint256 => mapping(uint256 => LoanDetails)) public Loans;
    uint256 public totalLoans = 0;
    // (poolId => noOfLoans)
    mapping(uint256 => uint256) public countLoansInPool;

    // (loanId => loanRepaymentiD[] => Details)
    mapping(uint256 => mapping(uint256 => LoanRepaymentDetails))
        public LoanRepayment;
    uint256 public totalLoanRepayments = 0;
    // (loanId => noOfLoanRepayments)
    mapping(uint256 => uint256) public countLoanRepaymentsForLoan;

    function getLoanByPoolID(uint256 poolId, uint256 loanId)
        external
        view
        returns (LoanDetails memory)
    {
        require(
            Loans[poolId][loanId].isExists,
            "getLoanByPoolID: No such record"
        );
        return Loans[poolId][loanId];
    }

    function getPoolByID(uint256 poolId)
        external
        view
        returns (PoolDetails memory)
    {
        require(Pools[poolId].isExists, "getPoolByID: No such record");
        return Pools[poolId];
    }

    function getCountLoansInPool(uint256 poolId)
        external
        view
        returns (uint256)
    {
        // console.log(Pools)
        require(Pools[poolId].isExists, "getCountLoansInPool: No such record");
        return countLoansInPool[poolId];
    }

    // POOL
    function _createPool(
        uint256 _amount,
        uint16 _paymentCycle,
        uint16 _APR,
        uint256 _durationInSecs,
        uint16 _durationInMonths,
        address _creator
    ) external onlyOwner returns (uint256) {
        uint256 poolId = totalPools;
        Pools[poolId] = PoolDetails(
            _amount,
            _paymentCycle,
            _APR,
            _durationInSecs,
            _durationInMonths,
            _creator,
            PoolStatus.OPEN,
            true
        );
        ++totalPools;
        return poolId;
    }

    function _updatePool(
        uint256 poolId,
        uint256 _amount,
        uint16 _paymentCycle,
        uint16 _APR,
        uint256 _durationInSecs,
        uint16 _durationInMonths,
        address _creator,
        PoolStatus status
    ) external onlyOwner {
        Pools[poolId] = PoolDetails(
            _amount,
            _paymentCycle,
            _APR,
            _durationInSecs,
            _durationInMonths,
            _creator,
            status,
            true
        );
    }

    function _isOpenLoansInPool(uint256 poolId) internal view returns (bool) {
        for (uint256 i = 0; i < countLoansInPool[poolId]; i++) {
            if (
                Loans[poolId][i].poolId == poolId &&
                Loans[poolId][i].status == LoanStatus.OPEN
            ) {
                return true;
            }
        }
        return false;
    }

    // LOAN
    function _createLoan(
        uint256 poolId,
        address borrowerAddress,
        uint256 principal
    ) external onlyOwner returns (uint256) {
        uint256 loanId = totalLoans;
        Loans[poolId][loanId] = LoanDetails(
            poolId,
            borrowerAddress,
            principal,
            LoanStatus.OPEN,
            true
        );
        ++totalLoans;
        countLoansInPool[poolId] = ++countLoansInPool[poolId];
        return loanId;
    }

    function _updateLoan(
        uint256 loanId,
        uint256 poolId,
        address borrowerAddress,
        uint256 principal,
        LoanStatus status
    ) external onlyOwner {
        Loans[poolId][loanId] = LoanDetails(
            poolId,
            borrowerAddress,
            principal,
            status,
            true
        );
    }

    function _createLoanRepayment(
        uint256 loanId,
        uint256 amount,
        LoanRepaymentType repaymentType
    ) external onlyOwner returns (uint256) {
        uint256 loanRepayment = totalLoanRepayments;
        LoanRepayment[loanId][loanRepayment] = LoanRepaymentDetails(
            loanId,
            amount,
            repaymentType,
            true
        );
        ++totalLoanRepayments;
        countLoanRepaymentsForLoan[loanId] = ++countLoanRepaymentsForLoan[
            loanId
        ];
        return loanRepayment;
    }

    function _hasPendingLoanRepayment(uint256 poolId)
        internal
        view
        returns (bool)
    {
        require(Pools[poolId].isExists, "Pool: Invalid pool Id!");
        // loan [i] -> loanId
        for (uint256 i = 0; i < countLoansInPool[poolId]; i++) {
            uint256 totalAmountRepaid;
            // loan repayments [j] -> loanRepaymentID
            for (uint256 j = 0; j < countLoanRepaymentsForLoan[i]; j++) {
                totalAmountRepaid += LoanRepayment[i][j].amount;
                if (totalAmountRepaid < Loans[poolId][i].principal) {
                    return true;
                }
            }
        }
        return false;
    }
}
