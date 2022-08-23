// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "./interfaces/IMarket.sol";
import "./interfaces/IPoolRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol":
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./PoolRegistry.sol";
import "./Escrow.sol";


contract Qredos is Ownable, PoolRegistry {
    using SafeERC20 for IERC20;

    IERC20 public paymentToken;
    IPoolRegistry public lendingPool = IPoolRegistry(lendingPoolAddress);

    uint32 public duration = 7776000; // APPROX. 90 days (3 months)
    uint32 public paymentCycle;
    uint16 public APR = 30; //  10% * 3 months
    uint16 public constant downPaymentPercentage = 50;   // borrowers will pay 50%

    // (borrowerAddress => mapping(PurchaseId => [])
    mapping(address => mapping(uint256 => PurchaseDetails)) public Purchase;
    uint256 public totalPurchases = 0;
    // (borrower => purchaseId)
    mapping(uint256 => uint256) countPurchaseForBorrower;

    bool public isPaused;


    enum PurchaseStatus {
        OPEN,
        COMPLETED,
        FAILED
    }

    struct PurchaseDetails{
        uint256 loanId;
        address escrowAddress;
        address tokenAddress;
        uint256 tokenId;
        PurchaseStatus;
        bool isExists;
    }


    event QredosContractDeployed(address paymentTokenAddress,address lendingPoolAddress);
    event LendingPoolUpdated(address oldValue, address newValue);
    event DurationUpdated(uint32 oldValue, uint32 newValue);
    event PaymentCycleUpdated(uint32 oldValue, uint32 newValue);
    event APRUpdated(uint16 oldValue, uint16 newValue);
    event PurchaseCreated(
        address indexed userAddress,
        uint256 indexed tokenId,
        address indexed tokenAddress,
        uint256 downPayment,
        uint256 principal,
        uint256 apr,
        uint32 duration,
        uint16 downPaymentPercentage
    );
    event PurchaseCompleted(uint256 indexed purchaseId);

    modifier whenNotPaused() {
        require(!isPaused, "Qredos: currently paused!");
        _;
    }

    constructor(address _paymentTokenAddress, address _lendingPoolAddress) {
        paymentToken = IERC20(_paymentTokenAddress);
    lendingPool = IPoolRegistry(_lendingPoolAddress);
        emit QredosContractDeployed(_paymentTokenAddress,_lendingPoolAddress);
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
        require(PoolRegistry(address(PoolRegistry)).Pools[poolId].isExists, "Qredos: Invalid pool!");
        require(
            _calcDownPayment(downPaymentAmount, principal),
            "Qredos: Invalid principal!"
        );
        require(lendingPool._getPoolBalance(poolId) > principal, "Qredos: Pool can't fund purchase!");
        uint256 loanId = lendingPool.requestLoan(poolId);
        require(paymentToken.balanceOf(address(this)) > (principal + downPaymentAmount), "Qredos: Qredos can't fund purchase!");
            paymentToken.safeTransferFrom(msg.sender, address(this), downPaymentAmount);

        require(
            paymentToken.balanceOf(address(this)) <
                (downPaymentAmount + principal),
            "Qredos: Insufficient funds!"
        );
        _createPurchase(msg.sender, loanId, address(0x0), tokenAddress, tokenId)

        emit PurchaseCreated(
            msg.sender,
            tokenId,
            tokenAddress,
            downPaymentAmount,
            principal,
            APR,
            duration,
            downPaymentPercentage
        );
    }

    function _completeNFTPurchase(uint256 purchaseId, address borrowerAddress){
        require(Purchase[borrowerAddress][poolId].isExists, "Qredos: Invalid purchase ID!");
        PurchaseDetails purchase = Purchase[borrowerAddress][poolId];
        require(ERC721(purchase.tokenAddress).ownerOf(purchase.tokenId) == address(this), "Qredos: Purchase Incomplete!");

        // update to proxy pattern to make deployment cheaper
        address escrowAddress =  address(new Escrow(borrowerAddress, purchase.tokenId,purchase.tokenAddress));
         require(Escrow(escrowAddress).owner() == address(this), "Qredos: Invalid escrow owner!");
        ERC721(purchase.tokenAddress).safeTransferFrom(address(this), escrowAddress, purchase.tokenId);
        _updatePurchase(
        borrowerAddress,
        purchaseId,
            purchase.loanId,
            purchase.escrowAddress,
            purchase.tokenAddress,
            purchase.tokenId,
            PurchaseStatus.COMPLETED,
            true
    )
        emit PurchaseCompleted(purchaseId)


    }

    function claimNft() public {}

    function liquidateNft() public {}

    function repayLoan() public {}

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

    function setLendingPoolAddress(address _newLendingPoolAddress)
        external
        onlyOwner
    {
        require(
            _newLendingPoolAddress != address(0x0),
            "Qredos: lending pool can't be zero"
        );
        address old = lendingPoolAddress;
        lendingPoolAddress = _newLendingPoolAddress;
        emit LendingPoolUpdated(old, _newLendingPoolAddress);
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
        paymentToken.transfer(owner(), paymentToken.balanceOf(address(this)));
    }

    /////////////////////////
    ///   Internal   ////////
    /////////////////////////


    function _createPurchase(uint256 borrowerAddress, uint256 loanId,
        address escrowAddress,
        address tokenAddress,
        uint256 tokenId)
        internal
        returns (uint256)
    {
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
            PurchaseStatus status,
            bool true
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
        view
        returns (bool)
    {
        uint16 rate = 100 / downPaymentPercentage;
        if (downPayment * rate == downPayment + principal) {
            return true;
        } else {
            return false;
        }
    }
    function _loanRequestId() internal{
        
    }
}
