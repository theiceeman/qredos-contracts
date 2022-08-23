// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "./interfaces/IMarket.sol";
import "./interfaces/ITellerV2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/* 
Polygon
    TellerV2: 0xD3D79A066F2cD471841C047D372F218252Dbf8Ed
    MarketRegistry: 0xeF0f89baC623eD7C875bC2F23b5403DcF90ba8Bd
Rinkeby: 
    TellerV2: 0x21d3D541937de52ac5e4aF6254d0d2134d9B7c9e
    MarketRegistry: 0xe2F925476d5A3b489d25efDbedE996E857974859
 */

contract Qredos is Ownable {
    IERC20 constant paymentToken;

    //  This will be set to Teller v2 initially. we can switch to our own pool in future.
    address public lendingPoolAddress =
        0x21d3D541937de52ac5e4aF6254d0d2134d9B7c9e;
    ITellerV2 public lendingPool = ITellerV2(lendingPoolAddress);

    uint256 public tellerMarketPlaceId = 0;
    uint32 public duration = 7776000; // APPROX. 90 days (3 months)
    uint32 public paymentCycle;
    uint16 public APR = 30; //  10% * 3 months
    uint16 public downPaymentPercentage = 50;

    bool public isPaused;

    event QredosContractDeployed();
    event LendingPoolUpdated(address oldValue, address newValue);
    event DurationUpdated(uint32 oldValue, uint32 newValue);
    event PaymentCycleUpdated(uint32 oldValue, uint32 newValue);
    event APRUpdated(uint16 oldValue, uint16 newValue);
    event TellerMarketPlaceIdUpdated(uint256 oldValue, uint256 newValue);
    event LoanApproved(
        address indexed userAddress,
        uint256 indexed tokenId,
        address indexed tokenAddress,
        uint256 downPayment,
        uint256 principal,
        uint256 apr,
        uint32 duration,
        uint16 downPaymentPercentage
    );

    modifier whenNotPaused() {
        require(!isPaused, "Qredos: currently paused!");
        _;
    }

    constructor(address _paymentTokenAddress) {
        paymentToken = IERC20(_paymentTokenAddress);
        emit QredosContractDeployed();
    }

    /*
        make sure escrow is owned by oracle before transferring nft to it. 
    */
    function buyNft(
        address tokenAddress,
        uint256 tokenId,
        uint256 downPaymentAmount,
        uint256 amountToBeLoaned
    ) public whenNotPaused {
        require(
            tokenAddress != address(0x0),
            "Escrow: address is zero address!"
        );
        require(
            _calcDownPayment(downPaymentAmount, amountToBeLoaned),
            "Qredos: Invalid principal!"
        );
        require(
            paymentToken.safeTransferFrom(msg.sender, address(this), downPaymentAmount),
            "Qredos: Transfer failed!"
        );

        lendingPool.submitBid(
            address(paymentToken),
            tellerMarketPlaceId,
            amountToBeLoaned,
            duration,
            APR,
            "https://ipfs.io/ipfs/QmbePdpATtZscRZcgFSaAsPuqKBsffWoYikqLxTbYkfrkW",
            address(this)
        );
        require(
            paymentToken.balanceOf(address(this)) <
                (downPaymentAmount + amountToBeLoaned),
            "Qredos: Insufficient funds!"
        );
        emit LoanApproved(
            msg.sender,
            tokenId,
            tokenAddress,
            downPaymentAmount,
            amountToBeLoaned,
            APR,
            duration,
            downPaymentPercentage
        );
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

    function setTellerMarketPlaceId(uint256 _tellerMarketPlaceId)
        external
        onlyOwner
    {
        require(
            _tellerMarketPlaceId != 0,
            "Qredos: marketplace ID can't be zero"
        );
        uint256 old = tellerMarketPlaceId;
        tellerMarketPlaceId = _tellerMarketPlaceId;
        emit TellerMarketPlaceIdUpdated(old, _tellerMarketPlaceId);
    }

    function forwardAllFunds() external onlyOwner {
        paymentToken.transfer(owner(), paymentToken.balanceOf(address(this)));
    }

    /////////////////////////
    ///   Internal   ////////
    /////////////////////////

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
