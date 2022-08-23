// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

interface IPoolRegistry {
    function createPool(
        uint256 _amount,
        uint16 _paymentCycle,
        uint16 _APR,
        uint256 _durationInSecs,
        uint16 _durationInMonths,
        address _creator
    ) external;

    function getValidPools(uint256 principal)
        external
        view
        returns (uint256[] memory);

    function requestLoan(
        uint256 principal,
        uint256 poolId,
        address borrower
    ) external returns(uint256);
    function repayLoanFull(
        uint256 loanId,
        uint256 amount,
        uint256 poolId
    ) external;
    function repayLoanPart(
        uint256 loanId,
        uint256 amount,
        uint256 poolId
    ) external;
    function fundPool(uint256 poolId, uint256 amount) external;
    function closePool(uint256 poolId, address reciever);
}
