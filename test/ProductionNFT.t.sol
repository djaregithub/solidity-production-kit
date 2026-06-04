// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {ProductionNFT} from "../src/ProductionNFT.sol";

contract ProductionNFTTest is Test {
    ProductionNFT public nft;
    address public owner = address(0x1);
    address public user = address(0x2);
    address public user2 = address(0x3);

    uint256 constant MAX_SUPPLY = 1000;
    uint256 constant MINT_PRICE = 0.01 ether;
    uint256 constant MAX_PER_WALLET = 5;

    function setUp() public {
        vm.prank(owner);
        nft = new ProductionNFT(
            "TestNFT", "TNFT",
            MAX_SUPPLY, MINT_PRICE, MAX_PER_WALLET,
            "ipfs://hidden/",
            owner
        );
    }

    // =============== CONSTRUCTOR ===============

    function test_Constructor() public {
        assertEq(nft.name(), "TestNFT");
        assertEq(nft.symbol(), "TNFT");
        assertEq(nft.maxSupply(), MAX_SUPPLY);
        assertEq(nft.mintPrice(), MINT_PRICE);
        assertEq(nft.maxPerWallet(), MAX_PER_WALLET);
        assertEq(nft.owner(), owner);
        assertFalse(nft.revealed());
    }

    // =============== MINT ===============

    function test_Mint() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        nft.mint{value: MINT_PRICE * 2}(2);

        assertEq(nft.totalMinted(), 2);
        assertEq(nft.ownerOf(1), user);
        assertEq(nft.ownerOf(2), user);
        assertEq(nft.mintedPerWallet(user), 2);
    }

    function test_RevertWhen_MintExceedsMaxPerWallet() public {
        vm.deal(user, 10 ether);
        vm.startPrank(user);
        nft.mint{value: MINT_PRICE * 5}(5);
        vm.expectRevert(ProductionNFT.MaxPerWalletExceeded.selector);
        nft.mint{value: MINT_PRICE}(1);
        vm.stopPrank();
    }

    function test_RevertWhen_MintInsufficientPayment() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(ProductionNFT.InsufficientPayment.selector);
        nft.mint{value: 0.001 ether}(1);
    }

    // =============== WHITELIST ===============

    function test_WhitelistMint() public {
        address[] memory whitelistUsers = new address[](1);
        whitelistUsers[0] = user;
        
        vm.prank(owner);
        nft.setWhitelist(whitelistUsers, true);

        vm.deal(user, 1 ether);
        vm.prank(user);
        nft.whitelistMint{value: MINT_PRICE}(1);

        assertEq(nft.totalMinted(), 1);
    }

    function test_RevertWhen_NonWhitelistedMints() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(ProductionNFT.NotWhitelisted.selector);
        nft.whitelistMint{value: MINT_PRICE}(1);
    }

    // =============== REVEAL ===============

    function test_Reveal() public {
        assertFalse(nft.revealed());

        vm.prank(owner);
        nft.reveal("ipfs://metadata/");

        assertTrue(nft.revealed());
        assertEq(nft.tokenURI(1), string.concat("ipfs://metadata/", vm.toString(1)));
    }

    function test_RevertWhen_DoubleReveal() public {
        vm.prank(owner);
        nft.reveal("ipfs://metadata/");

        vm.prank(owner);
        vm.expectRevert(ProductionNFT.AlreadyRevealed.selector);
        nft.reveal("ipfs://metadata/");
    }

    function test_RevertWhen_NonOwnerReveals() public {
        vm.prank(user);
        vm.expectRevert();
        nft.reveal("ipfs://metadata/");
    }

    // =============== WITHDRAW ===============

    function test_Withdraw() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        nft.mint{value: MINT_PRICE * 3}(3);

        uint256 contractBalance = address(nft).balance;
        assertEq(contractBalance, MINT_PRICE * 3);

        uint256 ownerBefore = owner.balance;
        vm.prank(owner);
        nft.withdraw();

        assertEq(owner.balance, ownerBefore + MINT_PRICE * 3);
        assertEq(address(nft).balance, 0);
    }

    function test_RevertWhen_NonOwnerWithdraws() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        nft.mint{value: MINT_PRICE}(1);

        vm.prank(user);
        vm.expectRevert();
        nft.withdraw();
    }

    // =============== OWNER FUNCTIONS ===============

    function test_SetMintPrice() public {
        vm.prank(owner);
        nft.setMintPrice(0.02 ether);
        assertEq(nft.mintPrice(), 0.02 ether);
    }
}
