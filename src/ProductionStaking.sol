// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ProductionStaking — Single-sided staking with reward distribution
/// @notice Stake ERC20 tokens and earn rewards based on duration
/// @dev Features: stake, unstake, claim rewards, emergency withdraw, variable APR
contract ProductionStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;
    
    uint256 public rewardRate; // rewards per second per total staked (scaled by 1e18)
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalStaked;
    uint256 public minStakingDuration = 7 days;
    uint256 public emergencyPenalty = 500; // 5% in basis points

    mapping(address => uint256) public userStaked;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public userRewards;
    mapping(address => uint256) public stakeTimestamp;

    error ZeroAmount();
    error InsufficientBalance();
    error MinDurationNotMet();
    error NoRewards();
    error TransferFailed();

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount, uint256 penalty);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate);

    constructor(
        address _stakingToken,
        address _rewardToken,
        address _initialOwner
    ) Ownable(_initialOwner) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            userRewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) return rewardPerTokenStored;
        return rewardPerTokenStored + (block.timestamp - lastUpdateTime) * rewardRate * 1e18 / totalStaked;
    }

    function earned(address account) public view returns (uint256) {
        return userStaked[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / 1e18 + userRewards[account];
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        userStaked[msg.sender] += amount;
        totalStaked += amount;
        stakeTimestamp[msg.sender] = block.timestamp;
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        if (userStaked[msg.sender] < amount) revert InsufficientBalance();

        userStaked[msg.sender] -= amount;
        totalStaked -= amount;

        // Check min duration
        uint256 penalty = 0;
        if (block.timestamp < stakeTimestamp[msg.sender] + minStakingDuration) {
            penalty = amount * emergencyPenalty / 10000;
        }

        stakingToken.safeTransfer(msg.sender, amount - penalty);
        emit Unstaked(msg.sender, amount, penalty);
    }

    function claimRewards() external nonReentrant updateReward(msg.sender) {
        uint256 reward = userRewards[msg.sender];
        if (reward == 0) revert NoRewards();
        userRewards[msg.sender] = 0;
        rewardToken.safeTransfer(msg.sender, reward);
        emit RewardsClaimed(msg.sender, reward);
    }

    function setRewardRate(uint256 _rewardRate) external onlyOwner updateReward(address(0)) {
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate);
    }

    function setMinDuration(uint256 _duration) external onlyOwner {
        minStakingDuration = _duration;
    }

    function setEmergencyPenalty(uint256 _penalty) external onlyOwner {
        emergencyPenalty = _penalty;
    }

    function fundRewards(uint256 amount) external onlyOwner {
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
    }
}
