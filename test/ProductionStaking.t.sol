// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {ProductionStaking} from "../src/ProductionStaking.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockStakingToken is ERC20 {
    constructor() ERC20("Stake", "STK") { _mint(msg.sender, 1_000_000e18); }
}

contract MockRewardToken is ERC20 {
    constructor() ERC20("Reward", "RWD") { _mint(msg.sender, 1_000_000e18); }
}

contract ProductionStakingTest is Test {
    ProductionStaking public staking;
    MockStakingToken public stakingToken;
    MockRewardToken public rewardToken;
    
    address public owner = address(0x1);
    address public user = address(0x2);
    address public user2 = address(0x3);

    uint256 constant STAKE_AMOUNT = 1000e18;

    function setUp() public {
        stakingToken = new MockStakingToken();
        rewardToken = new MockRewardToken();
        
        stakingToken.transfer(user, STAKE_AMOUNT);
        stakingToken.transfer(user2, STAKE_AMOUNT);
        
        staking = new ProductionStaking(address(stakingToken), address(rewardToken), owner);
        
        // Fund rewards
        rewardToken.transfer(address(staking), 100_000e18);
        vm.prank(owner);
        staking.setRewardRate(1e15); // 0.1% per second
    }

    function test_Constructor() public {
        assertEq(address(staking.stakingToken()), address(stakingToken));
        assertEq(address(staking.rewardToken()), address(rewardToken));
        assertEq(staking.owner(), owner);
        assertEq(staking.totalStaked(), 0);
    }

    function test_Stake() public {
        vm.startPrank(user);
        stakingToken.approve(address(staking), STAKE_AMOUNT);
        staking.stake(STAKE_AMOUNT);
        vm.stopPrank();

        assertEq(staking.userStaked(user), STAKE_AMOUNT);
        assertEq(staking.totalStaked(), STAKE_AMOUNT);
    }

    function test_UnstakeAfterMinPeriod() public {
        _stake(user, STAKE_AMOUNT);
        
        vm.warp(block.timestamp + 8 days); // past min duration
        vm.prank(user);
        staking.unstake(STAKE_AMOUNT);

        assertEq(staking.userStaked(user), 0);
        assertEq(staking.totalStaked(), 0);
        assertEq(stakingToken.balanceOf(user), STAKE_AMOUNT); // no penalty
    }

    function test_EmergencyPenalty() public {
        _stake(user, STAKE_AMOUNT);
        
        // Unstake before min duration
        vm.warp(block.timestamp + 1 days);
        vm.prank(user);
        staking.unstake(STAKE_AMOUNT);

        uint256 penalty = STAKE_AMOUNT * 500 / 10000; // 5%
        assertEq(stakingToken.balanceOf(user), STAKE_AMOUNT - penalty);
    }

    function test_ClaimRewards() public {
        _stake(user, STAKE_AMOUNT);
        
        vm.warp(block.timestamp + 10 days);
        vm.prank(user);
        staking.claimRewards();

        uint256 expectedReward = STAKE_AMOUNT * 1e15 * 10 days / 1e18;
        assertTrue(rewardToken.balanceOf(user) > 0);
    }

    function test_RevertWhen_UnstakeMoreThanStaked() public {
        _stake(user, STAKE_AMOUNT);
        
        vm.prank(user);
        vm.expectRevert(ProductionStaking.InsufficientBalance.selector);
        staking.unstake(STAKE_AMOUNT + 1);
    }

    function test_RevertWhen_ClaimNoRewards() public {
        _stake(user, STAKE_AMOUNT);
        vm.prank(user);
        vm.expectRevert(ProductionStaking.NoRewards.selector);
        staking.claimRewards(); // no time passed yet
    }

    function test_FundRewards() public {
        rewardToken.transfer(user, 1000e18);
        vm.startPrank(user);
        rewardToken.approve(address(staking), 1000e18);
        staking.fundRewards(1000e18);
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(address(staking)), 101_000e18);
    }

    // =============== HELPERS ===============
    
    function _stake(address who, uint256 amount) internal {
        vm.startPrank(who);
        stakingToken.approve(address(staking), amount);
        staking.stake(amount);
        vm.stopPrank();
    }
}
