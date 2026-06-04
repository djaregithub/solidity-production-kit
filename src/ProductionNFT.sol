// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ProductionNFT — ERC721 + URI Storage + Mint with Reveal
/// @notice Template for NFT collection with whitelist, reveal, and royalties
/// @dev Features: public mint, whitelist mint, reveal mechanism, max supply, per-wallet cap
contract ProductionNFT is ERC721URIStorage, Ownable, ReentrancyGuard {
    uint256 public immutable maxSupply;
    uint256 public mintPrice;
    uint256 public maxPerWallet;
    uint256 public totalMinted;
    
    string public baseURI;
    string public unrevealedURI;
    bool public revealed;
    
    mapping(address => uint256) public mintedPerWallet;
    mapping(address => bool) public whitelist;
    
    error MaxSupplyExceeded();
    error MaxPerWalletExceeded();
    error InsufficientPayment();
    error NotWhitelisted();
    error AlreadyRevealed();
    error WithdrawFailed();
    
    event MetadataRevealed(string baseURI);
    
    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _maxSupply,
        uint256 _mintPrice,
        uint256 _maxPerWallet,
        string memory _unrevealedURI,
        address _initialOwner
    ) ERC721(_name, _symbol) Ownable(_initialOwner) {
        maxSupply = _maxSupply;
        mintPrice = _mintPrice;
        maxPerWallet = _maxPerWallet;
        unrevealedURI = _unrevealedURI;
    }
    
    modifier canMint(uint256 amount) {
        if (totalMinted + amount > maxSupply) revert MaxSupplyExceeded();
        if (mintedPerWallet[msg.sender] + amount > maxPerWallet) revert MaxPerWalletExceeded();
        _;
    }
    
    function mint(uint256 amount) external payable canMint(amount) nonReentrant {
        if (msg.value < mintPrice * amount) revert InsufficientPayment();
        _batchMint(msg.sender, amount);
    }
    
    function whitelistMint(uint256 amount) external payable canMint(amount) nonReentrant {
        if (!whitelist[msg.sender]) revert NotWhitelisted();
        if (msg.value < mintPrice * amount) revert InsufficientPayment();
        _batchMint(msg.sender, amount);
    }
    
    function _batchMint(address to, uint256 amount) internal {
        for (uint256 i; i < amount; i++) {
            uint256 tokenId = totalMinted + i + 1;
            _safeMint(to, tokenId);
        }
        totalMinted += amount;
        mintedPerWallet[to] += amount;
    }
    
    function reveal(string memory _baseURI) external onlyOwner {
        if (revealed) revert AlreadyRevealed();
        revealed = true;
        baseURI = _baseURI;
        emit MetadataRevealed(_baseURI);
    }
    
    function _baseURI() internal view override returns (string memory) {
        return revealed ? baseURI : unrevealedURI;
    }
    
    function setWhitelist(address[] calldata addresses, bool status) external onlyOwner {
        for (uint256 i; i < addresses.length; i++) {
            whitelist[addresses[i]] = status;
        }
    }
    
    function setMintPrice(uint256 _mintPrice) external onlyOwner {
        mintPrice = _mintPrice;
    }
    
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = owner().call{value: balance}("");
        if (!success) revert WithdrawFailed();
    }
    
    function totalSupply() external view returns (uint256) {
        return totalMinted;
    }
}
