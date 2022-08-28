// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;
import "./models/Schema.sol";
import "./models/Events.sol";

import "./interfaces/IPoolRegistry.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./PoolRegistry.sol";
import "./Escrow.sol";
import "./store/PoolRegistryStore.sol";

abstract contract Qredos is Ownable, Schema, PoolRegistry {
    using SafeERC20 for IERC20;

    address public paymentTokenAddress;
    address public lendingPoolAddress;
    address public poolRegistryStoreAddress;

    uint32 public duration = 7776000; // APPROX. 90 days (3 months)
    uint32 public paymentCycle;
    uint16 public APR = 30; //  10% * 3 months
    uint16 public constant downPaymentPercentage = 50; // borrowers will pay 50%

    // (borrowerAddress => mapping(PurchaseId => [])
    mapping(address => mapping(uint256 => PurchaseDetails)) public Purchase;
    uint256 public totalPurchases = 0;
    // (borrower => purchaseId)
    mapping(address => uint256) countPurchaseForBorrower;

    bool public isPaused;

    enum PurchaseStatus {
        OPEN,
        COMPLETED,
        FAILED
    }

    struct PurchaseDetails {
        uint256 loanId;
        address escrowAddress;
        address tokenAddress;
        uint256 tokenId;
        PurchaseStatus status;
        bool isExists;
    }

    event QredosContractDeployed(
        address paymentTokenAddress,
        address lendingPoolAddress,
        address poolRegistryStoreAddress
    );
    event LendingPoolUpdated(address oldValue, address newValue);
    event DurationUpdated(uint32 oldValue, uint32 newValue);
    event PaymentCycleUpdated(uint32 oldValue, uint32 newValue);
    event APRUpdated(uint16 oldValue, uint16 newValue);
    event PurchaseCreated(
        address indexed userAddress,
        uint256 indexed poolId,
        uint256 indexed purchaseId,
        uint256 tokenId,
        address tokenAddress,
        uint256 downPayment,
        uint256 principal,
        uint256 apr,
        uint32 duration,
        uint16 downPaymentPercentage
    );
    event PurchaseCompleted(uint256 indexed purchaseId);
    event NFTClaimed(uint256 indexed purchaseId, address claimer);

    modifier whenNotPaused() {
        require(!isPaused, "Qredos: currently paused!");
        _;
    }

    constructor(
        address _paymentTokenAddress,
        address _lendingPoolAddress,
        address _PoolRegistryStoreAddress
    ) {
        paymentTokenAddress = _paymentTokenAddress;
        lendingPoolAddress = _lendingPoolAddress;
        poolRegistryStoreAddress = _PoolRegistryStoreAddress;
        emit QredosContractDeployed(
            _paymentTokenAddress,
            _lendingPoolAddress,
            _PoolRegistryStoreAddress
        );
    }

    /*
        make sure escrow is owned by oracle before transferring nft to it. 
    */
    function purchaseNFT(
        address tokenAddress,
        uint256 tokenId,
        uint256 downPaymentAmount,
        uint256 principal,
        uint256 poolId
    ) public whenNotPaused {
        require(
            tokenAddress != address(0x0),
            "Qredos: address is zero address!"
        );
        PoolRegistryStore _poolRegistryStore = PoolRegistryStore(
            poolRegistryStoreAddress
        );
        PoolDetails memory Pool = _poolRegistryStore.getPoolByID(poolId);
        require(Pool.isExists, "Qredos: Invalid pool!");
        require(
            _calcDownPayment(downPaymentAmount, principal),
            "Qredos: Invalid principal!"
        );
        require(
            PoolRegistry(lendingPoolAddress)._getPoolBalance(poolId) >
                principal,
            "Qredos: Pool can't fund purchase!"
        );
        uint256 loanId = IPoolRegistry(lendingPoolAddress).requestLoan(
            principal,
            poolId,
            msg.sender
        );
        require(
            IERC20(paymentTokenAddress).balanceOf(address(this)) >
                (principal + downPaymentAmount),
            "Qredos: Qredos can't fund purchase!"
        );
        IERC20(paymentTokenAddress).safeTransferFrom(
            msg.sender,
            address(this),
            downPaymentAmount
        );

        require(
            IERC20(paymentTokenAddress).balanceOf(address(this)) <
                (downPaymentAmount + principal),
            "Qredos: Insufficient funds!"
        );
        uint256 purchaseId = _createPurchase(
            msg.sender,
            loanId,
            address(0x0),
            tokenAddress,
            tokenId
        );

        emit PurchaseCreated(
            msg.sender,
            poolId,
            purchaseId,
            tokenId,
            tokenAddress,
            downPaymentAmount,
            principal,
            APR,
            duration,
            downPaymentPercentage
        );
    }

    function _completeNFTPurchase(uint256 purchaseId, address borrowerAddress)
        public
    {
        require(
            Purchase[borrowerAddress][purchaseId].isExists,
            "Qredos: Invalid purchase ID!"
        );
        PurchaseDetails memory purchase = Purchase[borrowerAddress][purchaseId];
        require(
            ERC721(purchase.tokenAddress).ownerOf(purchase.tokenId) ==
                address(this),
            "Qredos: Purchase Incomplete!"
        );

        // update to proxy pattern to make deployment cheaper
        address escrowAddress = address(
            new Escrow(borrowerAddress, purchase.tokenId, purchase.tokenAddress)
        );
        require(
            Escrow(escrowAddress).owner() == address(this),
            "Qredos: Invalid escrow owner!"
        );
        ERC721(purchase.tokenAddress).approve(escrowAddress, purchase.tokenId);
        Escrow(escrowAddress).deposit(purchase.tokenId, purchase.tokenAddress);

        _updatePurchase(
            borrowerAddress,
            purchaseId,
            purchase.loanId,
            purchase.escrowAddress,
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
    ) external returns (bool) {
        require(
            Purchase[msg.sender][purchaseId].isExists,
            "Qredos: Invalid purchase ID!"
        );
        PurchaseDetails memory purchase = Purchase[msg.sender][purchaseId];
        LoanDetails memory loan = PoolRegistryStore(poolRegistryStoreAddress)
            .getLoanByPoolID(poolId, purchase.loanId);
        if (repaymentType == LoanRepaymentType.FULL) {
            lendingToken.safeTransferFrom(
                msg.sender,
                address(this),
                loan.principal
            );
            IPoolRegistry(lendingPoolAddress).repayLoanFull(
                purchase.loanId,
                loan.principal,
                poolId
            );
        } else if (repaymentType == LoanRepaymentType.PART) {
            uint256 partPayment = _calcLoanPartPayment(purchase.loanId, poolId);
            lendingToken.safeTransferFrom(
                msg.sender,
                address(this),
                partPayment
            );
            IPoolRegistry(lendingPoolAddress).repayLoanPart(
                purchase.loanId,
                partPayment,
                poolId
            );
        }
        return true;
    }

    function claimNft(uint256 purchaseId, uint256 poolId) public {
        require(
            Purchase[msg.sender][purchaseId].isExists,
            "Qredos: Invalid purchase ID!"
        );
        PurchaseDetails memory purchase = Purchase[msg.sender][purchaseId];
        LoanDetails memory loan = PoolRegistryStore(poolRegistryStoreAddress)
            .getLoanByPoolID(poolId, purchase.loanId);
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

    function liquidateNft() public {}

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

    /// @dev set duration of loan requests.
    /// @param _duration - duration in seconds
    function setDuration(uint32 _duration) external onlyOwner {
        require(_duration != 0, "Qredos: duration can't be zero");
        uint32 old = duration;
        duration = _duration;
        emit DurationUpdated(old, _duration);
    }

    function setAPR(uint16 _APR) external onlyOwner {
        require(_APR != 0, "Qredos: APY can't be zero");
        uint16 old = APR;
        APR = _APR;
        emit APRUpdated(old, _APR);
    }

    function setPaymentCycle(uint32 _paymentCycle) external onlyOwner {
        require(_paymentCycle != 0, "Qredos: payment cycle can't be zero");
        uint32 old = paymentCycle;
        paymentCycle = _paymentCycle;
        emit PaymentCycleUpdated(old, _paymentCycle);
    }

    function forwardAllFunds() external onlyOwner {
        IERC20(paymentTokenAddress).transfer(
            owner(),
            IERC20(paymentTokenAddress).balanceOf(address(this))
        );
    }

    /////////////////////////
    ///   Internal   ////////
    /////////////////////////

    function _createPurchase(
        address borrowerAddress,
        uint256 loanId,
        address escrowAddress,
        address tokenAddress,
        uint256 tokenId
    ) internal returns (uint256) {
        uint256 purchases = totalPurchases;
        Purchase[borrowerAddress][purchases++] = PurchaseDetails(
            loanId,
            escrowAddress,
            tokenAddress,
            tokenId,
            PurchaseStatus.OPEN,
            true
        );
        ++totalPurchases;
        countPurchaseForBorrower[borrowerAddress] = countPurchaseForBorrower[
            borrowerAddress
        ]++;
        return purchases++;
    }

    function _updatePurchase(
        address borrowerAddress,
        uint256 purchaseId,
        uint256 loanId,
        address escrowAddress,
        address tokenAddress,
        uint256 tokenId,
        PurchaseStatus status
    ) internal {
        Purchase[borrowerAddress][purchaseId] = PurchaseDetails(
            loanId,
            escrowAddress,
            tokenAddress,
            tokenId,
            status,
            true
        );
    }

    function _calcDownPayment(uint256 downPayment, uint256 principal)
        internal
        pure
        returns (bool)
    {
        uint16 rate = 100 / downPaymentPercentage;
        if (downPayment * rate == downPayment + principal) {
            return true;
        } else {
            return false;
        }
    }

    function _loanRequestId() internal {}
}
