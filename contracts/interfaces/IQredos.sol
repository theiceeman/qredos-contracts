// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

interface IQredos {
    function purchaseNFT(
        address tokenAddress,
        uint256 tokenId,
        uint256 downPaymentAmount,
        uint256 principal,
        uint256 poolId
    ) external;

    function completeNFTPurchase(uint256 purchaseId)
        external;

    function repayLoan(
        uint256 purchaseId,
        LoanRepaymentType repaymentType,
        uint256 poolId
    ) external returns (bool);

    function claimNft(uint256 purchaseId, uint256 poolId) external;

    function startLiquidation(uint256 purchaseId, uint256 discountAmount)
        external;

    function completeLiquidation(uint256 liquidationId) external;

    function createPool(
        uint256 _amount,
        uint16 _paymentCycle,
        uint16 _APR,
        uint256 _durationInSecs,
        uint16 _durationInMonths,
        address _creator
    ) external;

    function fundPool(uint256 poolId, uint256 amount) external;

    function closePool(uint256 poolId, address reciever) external;

    function getPoolBalance(uint256 poolId) external view;

    enum LoanRepaymentType {
        FULL,
        PART
    }
}
