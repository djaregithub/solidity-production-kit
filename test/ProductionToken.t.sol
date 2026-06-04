// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {ProductionToken} from "../src/ProductionToken.sol";

contract ProductionTokenTest is Test {
    ProductionToken public token;
    address public owner = address(0x1);
    address public user = address(0x2);
    address public attacker = address(0x3);

    uint256 constant MAX_SUPPLY = 1_000_000e18;
    uint256 constant INITIAL_MINT = 100_000e18;

    function setUp() public {
        token = new ProductionToken("TestToken", "TST", MAX_SUPPLY, owner);
        vm.prank(owner);
        token.mint(user, INITIAL_MINT);
    }

    // =============== CONSTRUCTOR ===============

    function test_Constructor() public {
        assertEq(token.name(), "TestToken");
        assertEq(token.symbol(), "TST");
        assertEq(token.maxSupply(), MAX_SUPPLY);
        assertEq(token.owner(), owner);
        assertEq(token.totalSupply(), INITIAL_MINT);
        assertEq(token.balanceOf(user), INITIAL_MINT);
    }

    function test_RevertWhen_ZeroAddressOwner() public {
        vm.expectRevert(ProductionToken.ZeroAddress.selector);
        new ProductionToken("Test", "TST", MAX_SUPPLY, address(0));
    }

    // =============== MINT ===============

    function test_Mint() public {
        vm.prank(owner);
        token.mint(attacker, 100e18);
        assertEq(token.balanceOf(attacker), 100e18);
    }

    function test_RevertWhen_NonOwnerMints() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.mint(attacker, 100e18);
    }

    function test_RevertWhen_MintExceedsMaxSupply() public {
        uint256 remaining = MAX_SUPPLY - INITIAL_MINT;
        vm.prank(owner);
        vm.expectRevert(ProductionToken.ExceedsMaxSupply.selector);
        token.mint(attacker, remaining + 1);
    }

    // =============== BURN ===============

    function test_Burn() public {
        vm.prank(user);
        token.burn(10_000e18);
        assertEq(token.balanceOf(user), INITIAL_MINT - 10_000e18);
        assertEq(token.totalSupply(), INITIAL_MINT - 10_000e18);
    }

    // =============== PAUSE ===============

    function test_PausePreventsTransfer() public {
        vm.prank(owner);
        token.setPaused(true);
        
        vm.prank(user);
        vm.expectRevert(ProductionToken.Paused.selector);
        token.transfer(attacker, 1e18);
    }

    function test_OwnerCanUnpause() public {
        vm.prank(owner);
        token.setPaused(true);
        
        vm.prank(owner);
        token.setPaused(false);
        
        vm.prank(user);
        token.transfer(attacker, 1e18);
        assertEq(token.balanceOf(attacker), 1e18);
    }

    function test_RevertWhen_NonOwnerPauses() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.setPaused(true);
    }

    // =============== PERMIT (EIP-2612) ===============

    function test_Permit() public {
        (uint256 privateKey, address signer) = _makeAccount();
        token.mint(signer, 100e18);
        
        // Create permit
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(signer);
        
        // Sign permit
        bytes32 domainSeparator = _computeDomainSeparator();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                signer,
                attacker,
                50e18,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        
        // Use permit
        vm.prank(attacker);
        token.permit(signer, attacker, 50e18, deadline, v, r, s);
        assertEq(token.allowance(signer, attacker), 50e18);
    }

    // =============== HELPERS ===============

    function _makeAccount() internal returns (uint256, address) {
        uint256 pk = 0xABCD;
        return (pk, vm.addr(pk));
    }

    function _computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(token.name())),
                keccak256(bytes("1")),
                block.chainid,
                address(token)
            )
        );
    }
}
