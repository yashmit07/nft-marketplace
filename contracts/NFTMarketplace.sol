// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IMultiSigWallet {
    function isOwner(address owner) external view returns (bool);
}

contract NFTMarketplace is 
    Initializable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable 
{
    // Constants
    uint256 public constant MINIMUM_PRICE = 0.01 ether;
    
    address public multiSigWallet;
    
    struct Listing {
        address seller;
        uint256 price;
    }
    
    // State variables
    mapping(address => mapping(uint256 => Listing)) private s_listings;
    mapping(address => uint256) private s_proceeds;

    // Events
    event ItemListed(address indexed seller, address indexed nftAddress, uint256 indexed tokenId, uint256 price);
    event ItemCanceled(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);
    event ItemBought(address indexed buyer, address indexed nftAddress, uint256 indexed tokenId, uint256 price);

    // Custom errors
    error PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
    error NotListed(address nftAddress, uint256 tokenId);
    error AlreadyListed(address nftAddress, uint256 tokenId);
    error NoProceeds();
    error NotOwner();
    error NotApprovedForMarketplace();
    error PriceBelowMinimum();
    error NotMultiSigOwner();
    error InvalidMultiSigAddress();

    modifier onlyMultiSigOwner() {
        if (!IMultiSigWallet(multiSigWallet).isOwner(msg.sender)) 
            revert NotMultiSigOwner();
        _;
    }

    modifier priceCheck(uint256 price) {
        if (price < MINIMUM_PRICE) revert PriceBelowMinimum();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _multiSigWallet) 
        initializer 
        public 
    {
        if (_multiSigWallet == address(0)) revert InvalidMultiSigAddress();
        
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        multiSigWallet = _multiSigWallet;
    }

    function listItem(
        address nftAddress,
        uint256 tokenId,
        uint256 price
    ) external nonReentrant whenNotPaused priceCheck(price) returns (bool) {
        IERC721 nft = IERC721(nftAddress);
        if (nft.ownerOf(tokenId) != msg.sender) revert NotOwner();
        
        if(s_listings[nftAddress][tokenId].price > 0) revert AlreadyListed(nftAddress, tokenId);
        
        if (nft.getApproved(tokenId) != address(this)) {
            revert NotApprovedForMarketplace();
        }

        s_listings[nftAddress][tokenId] = Listing(msg.sender, price);
        emit ItemListed(msg.sender, nftAddress, tokenId, price);
        return true;
    }

    function cancelListing(
        address nftAddress,
        uint256 tokenId
    ) external nonReentrant {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price <= 0) revert NotListed(nftAddress, tokenId);
        if (listing.seller != msg.sender) revert NotOwner();
        
        delete s_listings[nftAddress][tokenId];
        emit ItemCanceled(msg.sender, nftAddress, tokenId);
    }

    function buyItem(
        address nftAddress,
        uint256 tokenId
    ) external payable nonReentrant whenNotPaused {
        Listing memory listedItem = s_listings[nftAddress][tokenId];
        if (listedItem.price <= 0) revert NotListed(nftAddress, tokenId);
        if (msg.value < listedItem.price) revert PriceNotMet(nftAddress, tokenId, listedItem.price);

        // Update proceeds before any external calls
        s_proceeds[listedItem.seller] += msg.value;
        delete s_listings[nftAddress][tokenId];
        
        IERC721(nftAddress).safeTransferFrom(listedItem.seller, msg.sender, tokenId);
        emit ItemBought(msg.sender, nftAddress, tokenId, listedItem.price);
    }

    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice
    ) external nonReentrant whenNotPaused priceCheck(newPrice) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price <= 0) revert NotListed(nftAddress, tokenId);
        if (listing.seller != msg.sender) revert NotOwner();

        s_listings[nftAddress][tokenId].price = newPrice;
        emit ItemListed(msg.sender, nftAddress, tokenId, newPrice);
    }

    function withdrawProceeds() external nonReentrant {
        uint256 proceeds = s_proceeds[msg.sender];
        if (proceeds <= 0) revert NoProceeds();
        
        s_proceeds[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: proceeds}("");
        require(success, "Transfer failed");
    }

    // Admin Functions
    function pause() external onlyMultiSigOwner {
        _pause();
    }

    function unpause() external onlyMultiSigOwner {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyMultiSigOwner 
    {}

    // View Functions
    function getListing(
        address nftAddress,
        uint256 tokenId
    ) external view returns (Listing memory) {
        return s_listings[nftAddress][tokenId];
    }

    function getProceeds(address seller) external view returns (uint256) {
        return s_proceeds[seller];
    }

    function getMinimumPrice() external pure returns (uint256) {
        return MINIMUM_PRICE;
    }
}