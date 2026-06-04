// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {ProductionLaunchpad} from "../src/ProductionLaunchpad.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockSaleToken is ERC20 {
    constructor() ERC20("Sale", "SALE") { _mint(msg.sender, 10_000_000e18); }
}

contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") { _mint(msg.sender, 10_000_000e6); }
    function decimals() public view virtual override returns (uint8) { return 6; }
}

contract ProductionLaunchpadTest is Test {
    ProductionLaunchpad public launchpad;
    MockSaleToken public saleToken;
    MockUSDC public usdc;

    address public owner = address(0x1);
    address public user = address(0x2);
    address public user2 = address(0x3);

    uint256 START;
    uint256 END;
    uint256 SOFT_CAP = 1000e6;   // $1000 USDC
    uint256 HARD_CAP = 10000e6;  // $10000 USDC
    uint256 MIN_BUY = 10e6;      // $10 USDC
    uint256 MAX_BUY = 1000e6;    // $1000 USDC

    function setUp() public {
        saleToken = new MockSaleToken();
        usdc = new MockUSDC();

        START = block.timestamp + 1 days;
        END = START + 14 days;

        ProductionLaunchpad.VestingSchedule memory v = ProductionLaunchpad.VestingSchedule({
            cliffDays: 30,
            vestingDays: 90,
            tgePercent: 1000  // 10% at TGE
        });

        vm.prank(owner);
        launchpad = new ProductionLaunchpad(
            address(saleToken), address(usdc),
            START, END, SOFT_CAP, HARD_CAP, MIN_BUY, MAX_BUY,
            END + 7 days, v, owner
        );

        // Fund sale tokens
        saleToken.transfer(address(launchpad), 1_000_000e18);
        
        // Add stage
        vm.prank(owner);
        launchpad.addStage("Public", 100e18, 500_000e18); // 100 tokens per 1 USDC

        // Fund users
        usdc.transfer(user, 5000e6);
        usdc.transfer(user2, 5000e6);
    }

    function test_Constructor() public {
        assertEq(address(launchpad.saleToken()), address(saleToken));
        assertEq(launchpad.softCap(), SOFT_CAP);
        assertEq(launchpad.hardCap(), HARD_CAP);
        assertEq(launchpad.owner(), owner);
    }

    function test_Buy() public {
        vm.warp(START + 1);
        
        vm.startPrank(user);
        usdc.approve(address(launchpad), 100e6);
        launchpad.buy(0);
        vm.stopPrank();

        assertEq(launchpad.contributed(user), 100e6);
        assertEq(launchpad.stages(0).sold, 100e6 * 100e18 / 1e18); // tokens sold
    }

    function test_RevertWhen_BuyBeforeStart() public {
        vm.prank(user);
        usdc.approve(address(launchpad), 100e6);
        
        vm.prank(user);
        vm.expectRevert(ProductionLaunchpad.SaleNotActive.selector);
        launchpad.buy(0);
    }

    function test_RevertWhen_BuyExceedsMax() public {
        vm.warp(START + 1);
        
        vm.startPrank(user);
        usdc.approve(address(launchpad), 5000e6);
        vm.expectRevert(ProductionLaunchpad.MaxBuyExceeded.selector);
        launchpad.buy(0);
        vm.stopPrank();
    }

    function test_FinalizeSoftCapMet() public {
        _buyTokens(user, 2000e6);
        
        vm.warp(END + 1);
        vm.prank(owner);
        launchpad.finalize();

        assertTrue(launchpad.finalized());
        assertFalse(launchpad.refundEnabled());
    }

    function test_RefundIfSoftCapNotMet() public {
        _buyTokens(user, 100e6); // below soft cap of 1000 USDC
        
        vm.warp(END + 1);
        vm.prank(owner);
        launchpad.finalize();

        assertTrue(launchpad.refundEnabled());
    }

    function test_ClaimTokens() public {
        _buyTokens(user, 500e6);
        
        vm.warp(END + 1);
        vm.prank(owner);
        launchpad.finalize();

        // Fast forward past cliff
        vm.warp(END + 31 days);
        
        uint256 balanceBefore = saleToken.balanceOf(user);
        vm.prank(user);
        launchpad.claimTokens();
        uint256 balanceAfter = saleToken.balanceOf(user);

        assertTrue(balanceAfter > balanceBefore);
        assertTrue(launchpad.claimed(user) > 0);
    }

    // =============== HELPERS ===============
    
    function _buyTokens(address who, uint256 amount) internal {
        vm.warp(START + 1);
        vm.startPrank(who);
        usdc.approve(address(launchpad), amount);
        launchpad.buy(0);
        vm.stopPrank();
    }
}
