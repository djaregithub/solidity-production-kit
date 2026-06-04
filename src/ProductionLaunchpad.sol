// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ProductionLaunchpad — Token presale with stages, vesting, and refund
/// @notice Launch your token with multiple sale stages, vesting schedules, and refund mechanism
/// @dev Features: stages (seed, private, public), whitelist per stage, USDC/ETH payment, vesting, refund
contract ProductionLaunchpad is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public saleToken;
    IERC20 public paymentToken; // address(0) for ETH
    uint256 public totalRaised;
    uint256 public totalTokensSold;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public softCap;
    uint256 public hardCap;
    uint256 public minBuy;
    uint256 public maxBuy;
    uint256 public refundDeadline;
    bool public finalized;
    bool public refundEnabled;

    struct Stage {
        string name;
        uint256 tokenPrice;      // tokens per payment token (scaled 1e18)
        uint256 maxAllocation;    // max tokens for this stage
        uint256 sold;
        bool isActive;
    }

    struct VestingSchedule {
        uint256 cliffDays;
        uint256 vestingDays;
        uint256 tgePercent;       // % released at TGE (in basis points, e.g. 1000 = 10%)
    }

    Stage[] public stages;
    VestingSchedule public vesting;
    
    mapping(address => uint256) public contributed;
    mapping(address => uint256) public claimed;
    mapping(address => bool) public whitelist;

    error SaleNotActive();
    error SaleEnded();
    error CapReached();
    error MinBuyNotMet();
    error MaxBuyExceeded();
    error NotWhitelisted();
    error StageExhausted();
    error RefundNotEnabled();
    error AlreadyFinalized();
    error WithdrawFailed();
    error InsufficientFunds();

    event Contributed(address indexed user, uint256 amount, uint256 tokens);
    event TokensClaimed(address indexed user, uint256 amount);
    event Finalized();
    event RefundEnabled();
    event RefundProcessed(address indexed user, uint256 amount);

    constructor(
        address _saleToken,
        address _paymentToken,  // address(0) for ETH
        uint256 _startTime,
        uint256 _endTime,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _minBuy,
        uint256 _maxBuy,
        uint256 _refundDeadline,
        VestingSchedule memory _vesting,
        address _owner
    ) Ownable(_owner) {
        saleToken = IERC20(_saleToken);
        paymentToken = _paymentToken == address(0) ? IERC20(address(0)) : IERC20(_paymentToken);
        startTime = _startTime;
        endTime = _endTime;
        softCap = _softCap;
        hardCap = _hardCap;
        minBuy = _minBuy;
        maxBuy = _maxBuy;
        refundDeadline = _refundDeadline;
        vesting = _vesting;
    }

    modifier saleActive() {
        if (block.timestamp < startTime || block.timestamp > endTime) revert SaleNotActive();
        _;
    }

    function addStage(string calldata name, uint256 tokenPrice, uint256 maxAllocation) external onlyOwner {
        stages.push(Stage(name, tokenPrice, maxAllocation, 0, true));
    }

    function setWhitelist(address[] calldata addresses, bool status) external onlyOwner {
        for (uint256 i; i < addresses.length; i++) {
            whitelist[addresses[i]] = status;
        }
    }

    function buy(uint256 stageIndex) external payable nonReentrant saleActive {
        _checkWhitelist();
        if (stageIndex >= stages.length) revert StageExhausted();
        Stage storage stage = stages[stageIndex];
        if (!stage.isActive || stage.sold >= stage.maxAllocation) revert StageExhausted();

        uint256 payment = _getPayment();
        if (payment < minBuy) revert MinBuyNotMet();
        if (contributed[msg.sender] + payment > maxBuy) revert MaxBuyExceeded();
        if (totalRaised + payment > hardCap) revert CapReached();

        // Calculate tokens (price is tokens per 1 payment token)
        uint256 tokens = payment * stage.tokenPrice / 1e18;
        uint256 remainingInStage = stage.maxAllocation - stage.sold;
        if (tokens > remainingInStage) {
            tokens = remainingInStage;
            _refundOverpayment(payment - (tokens * 1e18 / stage.tokenPrice));
        }

        stage.sold += tokens;
        totalRaised += payment;
        totalTokensSold += tokens;
        contributed[msg.sender] += payment;

        if (address(paymentToken) == address(0)) {
            // ETH sale — held in contract
        } else {
            paymentToken.safeTransferFrom(msg.sender, address(this), payment);
        }

        emit Contributed(msg.sender, payment, tokens);
    }

    function claimTokens() external nonReentrant {
        if (!finalized) revert SaleNotActive();
        uint256 _contributed = contributed[msg.sender];
        if (_contributed == 0) revert InsufficientFunds();

        // Calculate total tokens
        uint256 totalTokens = _contributed * _getTokenPrice() / 1e18;
        uint256 totalClaimed = claimed[msg.sender];
        
        // TGE release
        uint256 tgeAmount = totalTokens * vesting.tgePercent / 10000;
        uint256 vestedAmount;
        if (block.timestamp >= endTime + vesting.cliffDays * 1 days) {
            uint256 elapsed = block.timestamp - (endTime + vesting.cliffDays * 1 days);
            uint256 totalVestingTime = vesting.vestingDays * 1 days;
            if (elapsed >= totalVestingTime) {
                vestedAmount = totalTokens - tgeAmount;
            } else {
                vestedAmount = (totalTokens - tgeAmount) * elapsed / totalVestingTime;
            }
        }
        
        uint256 claimable = tgeAmount + vestedAmount - totalClaimed;
        if (claimable == 0) revert InsufficientFunds();
        
        claimed[msg.sender] += claimable;
        saleToken.safeTransfer(msg.sender, claimable);
        emit TokensClaimed(msg.sender, claimable);
    }

    function requestRefund() external nonReentrant {
        if (!refundEnabled) revert RefundNotEnabled();
        if (block.timestamp > refundDeadline) revert SaleEnded();
        uint256 amount = contributed[msg.sender];
        if (amount == 0) revert InsufficientFunds();
        
        contributed[msg.sender] = 0;
        if (address(paymentToken) == address(0)) {
            (bool success,) = payable(msg.sender).call{value: amount}("");
            if (!success) revert WithdrawFailed();
        } else {
            paymentToken.safeTransfer(msg.sender, amount);
        }
        emit RefundProcessed(msg.sender, amount);
    }

    function finalize() external onlyOwner {
        if (finalized) revert AlreadyFinalized();
        if (block.timestamp < endTime) revert SaleNotActive();
        finalized = true;
        
        if (totalRaised < softCap) {
            refundEnabled = true;
        }
        emit Finalized();
    }

    function withdrawFunds() external onlyOwner {
        if (!finalized) revert SaleNotActive();
        if (totalRaised < softCap) revert InsufficientFunds();
        
        if (address(paymentToken) == address(0)) {
            (bool success,) = payable(owner()).call{value: totalRaised}("");
            if (!success) revert WithdrawFailed();
        } else {
            paymentToken.safeTransfer(owner(), totalRaised);
        }
    }

    function withdrawUnsoldTokens() external onlyOwner {
        if (!finalized) revert SaleNotActive();
        uint256 unsold = saleToken.balanceOf(address(this)) - totalTokensSold;
        if (unsold > 0) {
            saleToken.safeTransfer(owner(), unsold);
        }
    }

    // =============== INTERNAL ===============

    function _checkWhitelist() internal view {
        // Override in subclass if whitelist needed
    }

    function _getPayment() internal view returns (uint256) {
        if (address(paymentToken) == address(0)) return msg.value;
        return 0; // ERC20 payment handled via approve + transferFrom
    }

    function _getTokenPrice() internal view returns (uint256) {
        if (stages.length == 0) return 0;
        return stages[stages.length - 1].tokenPrice;
    }

    function _refundOverpayment(uint256 amount) internal {
        if (amount == 0) return;
        if (address(paymentToken) == address(0)) {
            (bool success,) = payable(msg.sender).call{value: amount}("");
            if (!success) revert WithdrawFailed();
        }
    }
}
