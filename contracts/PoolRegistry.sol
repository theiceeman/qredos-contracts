// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PoolRegistry is Ownable {
    using SafeERC20 for IERC20;

    IERC20 private lendingToken;
    mapping(uint256 => PoolDetails) public Pools;
    uint256 public totalPools = 0;
    // (poolId => mapping(loanId => [])
    mapping(uint256 => mapping(uint256 => LoanDetails)) public Loans;
    uint256 public totalLoans = 0;
    // (pool => noOfLoans)
    mapping(uint256 => uint256) countLoansInPool;
    // (loanId => mapping(loanRepaymentiD => [])
    mapping(uint256 => mapping(uint256 => LoanRepaymentDetails))
        public LoanRepayment;
    uint256 public totalLoanRepayments = 0;

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
        MINIMUM
    }

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
        bool isExists;
    }

    event PoolRegistryContractDeployed();
    event PoolCreated(uint256 indexed poolId, address indexed creator);
    event LoanCreated(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 principal
    );
    event LoanRepaid(
        uint256 indexed loanRepaymentId,
        uint256 indexed loanId,
        uint256 amount,
        LoanRepaymentType
    );
    event PoolFunded(uint256 indexed poolId, uint256 amount);
    event PoolClosed(uint256 indexed poolId, uint256 amountWithdrawn);

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
    ) external {
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
        returns (uint256[] memory validPools)
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
    ) external {
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
    }

    function repayLoanFull(
        uint256 loanId,
        uint256 amount,
        uint256 poolId
    ) external {
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

    function repayLoanMinimum(
        uint256 loanId,
        uint256 amount,
        uint256 poolId
    ) external {
        require(
            Loans[poolId][loanId].isExists,
            "Pool.repayLoanMinimum: Invalid loan Id!"
        );
        require(amount > 0, "Pool.repayLoanMinimum: Invalid input!");
        // amount should equal percentage scheduled for one payment cycle
        require(
            amount ==
                Loans[poolId][loanId].principal /
                    Pools[Loans[poolId][loanId].principal].paymentCycle,
            "Pool.repayLoanMinimum: Invalid amount!"
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
            LoanRepaymentType.MINIMUM
        );
    }

    function fundPool(uint256 poolId, uint256 amount) external {
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

    function closePool(uint256 poolId, address reciever) external {
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

    // POOL
    function _createPool(
        uint256 _amount,
        uint16 _paymentCycle,
        uint16 _APR,
        uint256 _durationInSecs,
        uint16 _durationInMonths,
        address _creator
    ) internal returns (uint256 poolId) {
        uint256 poolId = totalPools;
        Pools[poolId++] = PoolDetails(
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
        return poolId++;
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
    ) internal {
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

    function _isOpenLoansInPool(uint256 poolId) internal {
        for (uint256 i = 0; i < countLoansInPool[poolId]; i++) {
            if (
                Loans[poolId][i].poolId == poolId &&
                Loans[poolId][i].status == LoanStatus.OPEN
            ) {
                return true;
            }
        }
    }

    // LOAN
    function _createLoan(
        uint256 poolId,
        address borrowerAddress,
        uint256 principal
    ) internal returns (uint256 loanId) {
        uint256 loanId = totalLoans;
        Loans[poolId][loanId++] = LoanDetails(
            poolId,
            borrowerAddress,
            principal,
            LoanStatus.OPEN,
            true
        );
        ++totalLoans;
        countLoansInPool[poolId] = countLoansInPool[poolId]++;
        return loanId++;
    }

    function _createLoanRepayment(uint256 loanId, uint256 amount)
        internal
        returns (uint256)
    {
        uint256 loanRepayment = totalLoanRepayments;
        LoanRepayment[loanId][loanRepayment++] = LoanRepaymentDetails(
            loanId,
            amount,
            true
        );
        ++totalLoanRepayments;
        return loanRepayment++;
    }

    function _hasPendingLoanRepayment(uint256 poolId) internal returns (bool) {
        require(Pools[poolId].isExists, "Pool: Invalid pool Id!");
        for (uint256 i = 0; i < Loans[poolId].length; i++) {
            uint256 totalAmountRepaid;
            for (uint256 j = 0; j < LoanRepayment[poolId][i].length; j++) {
                totalAmountRepaid += LoanRepayment[poolId][i].amount;
                if (totalAmountRepaid < Loans[poolId][i]) {
                    return true;
                }
            }
        }
        return false;
    }

    // (pool balance - total lent out) + total repaid
    // This is amout pool creator can currently withdraw
    function _getPoolBalanceWithInterest(uint256 poolId)
        internal
        returns (uint256)
    {
        uint256 totalAmountLoaned;
        uint256 totalAmountRepaid;
        for (uint256 i = 0; i < Loans[poolId].length; i++) {
            totalAmountLoaned += Loans[poolId][i].principal;
            for (uint256 j = 0; j < LoanRepayment[poolId][i].length; j++) {
                totalAmountRepaid += LoanRepayment[poolId][i].amount;
            }
        }
        return (Pools[poolId].amount - totalAmountLoaned) + totalAmountRepaid;
    }
}
