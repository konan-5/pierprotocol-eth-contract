// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract PierMarketplace is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Book {
        address seller;
        address sellTokenAddress;
        uint256 sellTokenAmount;
        address paymentTokenAddress;
        uint256 paymentTokenAmount;
        bool isActive;
    }

    struct BookForETH {
        address seller;
        address sellTokenAddress;
        uint256 sellTokenAmount;
        uint256 ETHAmount;
        bool isActive;
    }

    struct FriendToken {
        address tokenAddress;
        uint256 feeRate;
        bool isActive;
    }

    // Total number of listings
    uint256 public bookCount = 0;
    uint256 public bookForETHCount = 0;
    uint256 public friendTokenCount = 0;

    address public feeWallet;

    // mapping of all book listings
    mapping(uint256 => Book) public bookList;
    // mapping of all FriendToken list
    mapping(uint256 => FriendToken) public friendTokenList;

    // Blacklist mapping
    mapping(address => bool) private blackList;

    //Events
    event Booked(uint256 indexed bookId, address indexed seller, address indexed sellTokenAddress, uint256 sellTokenAmount, address paymentTokenAddress, uint256 paymentTokenAmount);
    event TokenPurchased(uint256 indexed bookId, address indexed buyer);
    event BookRemoved(uint256 indexed bookId);
    event FriendTokenAdded(address indexed tokenAddress, uint256 indexed feeRate);
    event FriendTokenRemoved(uint256 indexed friendTokenId);
    event FeeWalletAddressUpdated(address indexed feeWallet);


    //Errors
    error InvalidSellTokenAmount(uint256 amount);
    error InvalidPaymentTokenAmount(uint256 priceInWei);
    error InvalidSellTokenAddress(address tokenAddress);
    error InvalidPaymentTokenAddress(address paymentTokenAddress);
    error ListingDoesNotExist(uint256 listingId);
    error InsufficientAllowanceOfBuyer(uint256 buyerAllowance, uint256 paymentTokenAmount);
    error InsufficientBalanceOfBuyer(uint256 buyerBalance, uint256 paymentTokenAmount);
    error InsufficientAllowanceOfSeller(uint256 sellerAllowance, uint256 sellTokenAmount);
    error InsufficientAmountOfSeller(uint256 sellerBalance, uint256 sellTokenAmount);
    error OnlyTheSellerCanRemoveTheBook(address seller, address msgSender);
    error FriendTokeDoesNotExist(uint256 friendTokenId);
    error InvalidFriendTokenAddress(address tokenAddress);
    error InvalidFeeRate(uint256 feeRate);
    error InvalidFeeWalletAddress(address feeWallet);
    error InvalidPurchasePercent(uint256 purchasePercent);


    constructor(address _feeWallet) Ownable(msg.sender) {
        feeWallet = _feeWallet;
    }

    /* PUBLIC FUNCTIONS */

    function book(address sellTokenAddress, uint256 sellTokenAmount, address paymentTokenAddress, uint256 paymentTokenAmount) external nonReentrant {
        if (sellTokenAmount == 0) revert InvalidSellTokenAmount(sellTokenAmount);
        if (paymentTokenAmount == 0) revert InvalidPaymentTokenAmount(paymentTokenAmount);
        if (sellTokenAddress == address(0)) revert InvalidSellTokenAddress(sellTokenAddress);
        if (paymentTokenAddress == address(0)) revert InvalidPaymentTokenAddress(paymentTokenAddress);
        address sender = msg.sender;
        uint256 allowance = IERC20(sellTokenAddress).allowance(sender, address(this));
        require(allowance >= sellTokenAmount, "Marketplace does not have enough allowance to transfer tokens");

        // increase book count
        bookCount++;

        // Add listing to bookList map
        bookList[bookCount] = Book(
            sender,
            sellTokenAddress,
            sellTokenAmount,
            paymentTokenAddress,
            paymentTokenAmount,
            true
        );

        // Emit book event
        emit Booked(bookCount, sender, sellTokenAddress, sellTokenAmount, paymentTokenAddress, paymentTokenAmount);
    }

    function buyToken(uint256 bookId, uint256 purchasePercent) external nonReentrant {
        if (purchasePercent == 0 || purchasePercent > 100) revert InvalidPurchasePercent(purchasePercent);
        // Get listing from mapping
        Book memory bookItem = bookList[bookId];
        // Check if listing exists
        if (bookItem.paymentTokenAddress == address(0)) revert ListingDoesNotExist(bookId);

        // Check is listing is active
        if (!bookItem.isActive) revert ListingDoesNotExist(bookId);

        uint256 paymentTokenAmount = bookItem.paymentTokenAmount * purchasePercent / 100;
        uint256 sellTokenAmount = bookItem.sellTokenAmount * purchasePercent / 100;

        // Check if buyer has approved paymentToken to the marketplace
        uint256 buyerAllowance = IERC20(bookItem.paymentTokenAddress).allowance(msg.sender, address(this));
        if (buyerAllowance < paymentTokenAmount) revert InsufficientAllowanceOfBuyer(buyerAllowance, paymentTokenAmount);

        // Check if buyer has enough balance of paymentToken
        uint256 buyerBalance = IERC20(bookItem.paymentTokenAddress).balanceOf(msg.sender);
        if (buyerBalance < paymentTokenAmount) revert InsufficientBalanceOfBuyer(buyerBalance, paymentTokenAmount);

        // Check if seller has approved sellToken to the marketplace
        uint256 sellerAllowance = IERC20(bookItem.sellTokenAddress).allowance(bookItem.seller, address(this));
        if (sellerAllowance < sellTokenAmount) revert InsufficientAllowanceOfSeller(sellerAllowance, sellTokenAmount);

        // Check if the seller has enough tokens to sell.
        uint256 sellerBalance = IERC20(bookItem.sellTokenAddress).balanceOf(bookItem.seller);
        if (sellerBalance < sellTokenAmount) revert InsufficientAmountOfSeller(sellerBalance, sellTokenAmount);

        //Set listing isActive=false
        if(purchasePercent == 100)
        {
            bookItem.isActive = false;
        }else {
            bookItem.paymentTokenAmount -= paymentTokenAmount;
            bookItem.sellTokenAmount -= sellTokenAmount;
        }

        // Transfer the tokens from the seller to the buyer.
        IERC20(bookItem.sellTokenAddress).safeTransferFrom(bookItem.seller, msg.sender, sellTokenAmount);

        // Calculate the fee. seller pays for the fee.
        // (uint256 feeForStaking, uint256 feeForWallet) = _calculateFee(listing.priceInWei, listing.tokenAddress);

        uint256 fee = _calculateFee(bookItem);

        // Transfer the total fee to this contract
        IERC20(bookItem.paymentTokenAddress).safeTransferFrom(msg.sender, feeWallet, fee);

        // Transfer the remaining amount to the seller
        uint256 amountToSeller = paymentTokenAmount - fee;

        IERC20(bookItem.paymentTokenAddress).safeTransferFrom(msg.sender, bookItem.seller, amountToSeller);

        // Emit the TokenPurchased event.
        emit TokenPurchased(bookId, msg.sender);
    }

    function removeBook(uint256 bookId) external {
        // Get listing from mapping
        Book memory bookItem = bookList[bookId];

        // Check if listing exists
        if (bookItem.sellTokenAddress == address(0)) revert ListingDoesNotExist(bookId);

        // Check if msg.sender is the seller
        if (msg.sender != bookItem.seller) revert OnlyTheSellerCanRemoveTheBook(bookItem.seller, msg.sender);

        //Set listing isActive=false
        bookList[bookId].isActive = false;

        // Emit event
        emit BookRemoved(bookId);
    }

    /* Friendship Token */

    function addFriendToken(address tokenAddress, uint256 feeRate) external onlyOwner {
        if (tokenAddress == address(0)) revert InvalidFriendTokenAddress(tokenAddress);
        if (feeRate > 100) revert InvalidFeeRate(feeRate);
        friendTokenCount ++;
        friendTokenList[friendTokenCount] = FriendToken (
            tokenAddress,
            feeRate,
            true
        );

        emit FriendTokenAdded(tokenAddress, feeRate);
    }

    function removeFriendToken(uint256 friendTokenId) external onlyOwner {
        FriendToken memory friendToken = friendTokenList[friendTokenId];
        if (friendToken.tokenAddress == address(0)) revert FriendTokeDoesNotExist(friendTokenId);
        friendToken.isActive = false;

        emit FriendTokenRemoved(friendTokenId);
    }

    function updateFeeWallet(address walletAddress) external onlyOwner {
        if (walletAddress == address(0)) revert InvalidFeeWalletAddress(walletAddress);
        feeWallet = walletAddress;
        emit FeeWalletAddressUpdated(walletAddress);
    }

    /* INTERNAL FUNCTIONS */

    function _calculateFee(Book memory bookItem) internal view returns (uint256) {
        // If the token being transacted is pierToken, return zero fees
        uint256 fee = bookItem.paymentTokenAmount * 3 / 100;
        for(uint8 idx = 1; idx <= friendTokenCount; idx ++) {
            FriendToken memory friendToken = friendTokenList[idx];
            if(!friendToken.isActive) {
                continue;
            }
            if(bookItem.paymentTokenAddress == friendToken.tokenAddress) {
                fee = fee * friendToken.feeRate / 100;
            }
            if(bookItem.sellTokenAddress == friendToken.tokenAddress) {
                fee = fee * friendToken.feeRate / 100;
            }
            if (fee == 0) return 0;
        }
        return fee;
    }
}
