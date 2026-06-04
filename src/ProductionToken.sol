// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ProductionToken — ERC20 + Permit + Ownership + Security
/// @notice Template contract for production-ready token with Foundry test suite
/// @dev Features: mint, burn, pausable (via owner), EIP-2612 permit, max supply cap
contract ProductionToken is ERC20, ERC20Permit, Ownable {
    uint256 public immutable maxSupply;
    bool public paused;
    
    error Paused();
    error ExceedsMaxSupply();
    error ZeroAddress();
    
    event PausedStateSet(bool paused);
    
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        address _initialOwner
    ) ERC20(_name, _symbol) ERC20Permit(_name) Ownable(_initialOwner) {
        if (_initialOwner == address(0)) revert ZeroAddress();
        maxSupply = _maxSupply;
    }
    
    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        if (totalSupply() + amount > maxSupply) revert ExceedsMaxSupply();
        _mint(to, amount);
    }
    
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
    
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PausedStateSet(_paused);
    }
    
    function transfer(address to, uint256 value) public override whenNotPaused returns (bool) {
        return super.transfer(to, value);
    }
    
    function transferFrom(address from, address to, uint256 value) public override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, value);
    }
}
