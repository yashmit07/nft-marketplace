// SPDX-License-Identifier: MIT
// Referece: https://medium.com/coinmonks/how-to-create-erc-721-nfts-on-ethereum-with-openzeppelin-a-step-by-step-tutorial-47b252843dd9 
// Code Reference: https://wizard.openzeppelin.com/#erc721 

pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

interface IMultiSigWallet {
    function isOwner(address owner) external view returns (bool);
}

contract NFT is 
    Initializable, 
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    ERC721PausableUpgradeable,
    AccessControlUpgradeable,
    ERC721BurnableUpgradeable,
    UUPSUpgradeable 
{
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    uint256 private _nextTokenId;
    address public multiSigWallet;

    // Events
    event NFTMinted(address indexed to, uint256 indexed tokenId, string uri);
    
    // Custom errors
    error NotMultiSigOwner();
    error InvalidMultiSigAddress();

    modifier onlyMultiSigOwner() {
        if (msg.sender != multiSigWallet && !IMultiSigWallet(multiSigWallet).isOwner(msg.sender)) 
            revert NotMultiSigOwner();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _multiSigWallet,
        string memory name,
        string memory symbol
    ) initializer public {
        if (_multiSigWallet == address(0)) revert InvalidMultiSigAddress();

        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __ERC721Pausable_init();
        __AccessControl_init();
        __ERC721Burnable_init();
        __UUPSUpgradeable_init();

        multiSigWallet = _multiSigWallet;
        _grantRole(ADMIN_ROLE, _multiSigWallet);
        _grantRole(DEFAULT_ADMIN_ROLE, _multiSigWallet);
    }

    function safeMint(address to, string memory uri) 
        public 
        onlyMultiSigOwner 
        returns (uint256)
    {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        
        emit NFTMinted(to, tokenId, uri);
        return tokenId;
    }

    function burn(uint256 tokenId) 
        public 
        override 
    {
        require(!paused() || IMultiSigWallet(multiSigWallet).isOwner(_msgSender()), "Paused");
        require(
            ownerOf(tokenId) == _msgSender() || getApproved(tokenId) == _msgSender() || isApprovedForAll(ownerOf(tokenId), _msgSender()),
            "ERC721: caller is not token owner or approved"
        );
        _burn(tokenId);
    }

    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyRole(ADMIN_ROLE) 
        onlyMultiSigOwner 
    {}

    function pause() public onlyMultiSigOwner {
        _pause();
    }

    function unpause() public onlyMultiSigOwner {
        _unpause();
    }

    function isMultiSigOwner(address account) public view returns (bool) {
        return IMultiSigWallet(multiSigWallet).isOwner(account);
    }

    // Required overrides
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721PausableUpgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable, ERC721URIStorageUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // Helper functions for the marketplace
    function totalSupply() public view virtual override(ERC721EnumerableUpgradeable) returns (uint256) {
        return super.totalSupply();
    }
}