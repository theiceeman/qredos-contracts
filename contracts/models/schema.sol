// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

contract Schema {

    enum PoolStatus {
        OPEN,
        CLOSED
    }
    enum LoanStatus {
        OPEN,
        CLOSED
    }
    enum LoanRepaymentType {
        FULL,
        PART
    }
// PoolRegistry
struct PoolDetails {
    uint256 amount;
    uint16 paymentCycle;
    uint16 APR;
    uint256 durationInSecs;
    uint16 durationInMonths;
    address creator;
    PoolStatus status; //  OPEN | CLOSED
    bool isExists;
}
struct LoanDetails {
    uint256 poolId;
    address borrower;
    uint256 principal;
    LoanStatus status; //  OPEN | CLOSED
    bool isExists;
}
struct LoanRepaymentDetails {
    uint256 loanId;
    uint256 amount;
    LoanRepaymentType RepaymentType;
    bool isExists;
}
}