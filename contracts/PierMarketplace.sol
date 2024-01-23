// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Importing OpenZeppelin contracts for standard functionalities.
import "@openzeppelin/contracts/interfaces/IERC20.sol";  // Interface for ERC20 tokens.
import "@openzeppelin/contracts/access/Ownable.sol";     // Contract module to provide basic authorization control.
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // Modifier to prevent reentrancy attacks.
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; // Library for safe ERC20 interactions.

// Declaration of the PierMarketplace contract, inheriting from Ownable and ReentrancyGuard.
contract PierMarketplace is Ownable, ReentrancyGuard {
    // Utilizing SafeERC20 for safe ERC20 token interactions.
    using SafeERC20 for IERC20;

    // Structure defining a book for sale in terms of ERC20 tokens.
    struct Book {
        address seller;                 // Address of the seller.
        address sellTokenAddress;       // Address of the token being sold.
        uint256 sellTokenAmount;        // Amount of the token being sold.
        address paymentTokenAddress;    // Address of the token accepted as payment.
        uint256 paymentTokenAmount;     // Amount of payment token required.
        bool isActive;                  // Status of the listing (active/inactive).
    }
    
    // Counter for the total number of book listings.
    uint256 public bookCount = 0;

    // Address to collect fees.
    address public feeWallet;

    // Mapping of book listings, identified by a numeric ID.
    mapping(uint256 => Book) public bookList;
    // Mapping to store fee rates for friend tokens (identified by their address).
    mapping(address => uint8) public friendTokenFeeList;

    // Events to emit on various actions.
    event Booked(uint256 indexed bookId, address indexed seller, address indexed sellTokenAddress, uint256 sellTokenAmount, address paymentTokenAddress, uint256 paymentTokenAmount);
    event TokenPurchased(uint256 indexed bookId, address indexed buyer);
    event BookRemoved(uint256 indexed bookId);
    event FriendTokenUpdated(address indexed tokenAddress, uint256 indexed feeRate);
    event FeeWalletAddressUpdated(address indexed feeWallet);

    // Custom errors for specific revert conditions.
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
    error InvalidFriendTokenAddress(address tokenAddress);
    error InvalidFeeRate(uint256 feeRate);
    error InvalidFeeWalletAddress(address feeWallet);
    error InvalidPurchasePercent(uint256 purchasePercent);

    // Constructor to initialize the marketplace with a fee wallet address.
    constructor(address _feeWallet) Ownable(msg.sender) {
        feeWallet = _feeWallet;
    }

    // Function to create a book listing.
    function book(address sellTokenAddress, uint256 sellTokenAmount, address paymentTokenAddress, uint256 paymentTokenAmount) external nonReentrant {
        // Validations for the input parameters.
        if (sellTokenAmount == 0) revert InvalidSellTokenAmount(sellTokenAmount);
        if (paymentTokenAmount == 0) revert InvalidPaymentTokenAmount(paymentTokenAmount);
        if (sellTokenAddress == address(0)) revert InvalidSellTokenAddress(sellTokenAddress);
        if (paymentTokenAddress == address(0)) revert InvalidPaymentTokenAddress(paymentTokenAddress);

        // Fetching the sender's address and checking allowance.
        address sender = msg.sender;
        uint256 allowance = IERC20(sellTokenAddress).allowance(sender, address(this));
        require(allowance >= sellTokenAmount, "Marketplace does not have enough allowance to transfer tokens");

        // Incrementing book count and adding the book to the listing.
        bookCount++;
        bookList[bookCount] = Book(
            sender,
            sellTokenAddress,
            sellTokenAmount,
            paymentTokenAddress,
            paymentTokenAmount,
            true
        );

        // Emitting an event for the book creation.
        emit Booked(bookCount, sender, sellTokenAddress, sellTokenAmount, paymentTokenAddress, paymentTokenAmount);
    }

    // Function to buy tokens from a book listing.
    function buyToken(uint256 bookId, uint256 purchasePercent) external nonReentrant {
        // Validation for the purchase percentage.
        if (purchasePercent == 0 || purchasePercent > 100) revert InvalidPurchasePercent(purchasePercent);

        // Fetching the book item and validating its existence and activity status.
        Book memory bookItem = bookList[bookId];
        if (bookItem.paymentTokenAddress == address(0)) revert ListingDoesNotExist(bookId);
        if (!bookItem.isActive) revert ListingDoesNotExist(bookId);

        // Calculating the amount of tokens and payment to be made.
        uint256 paymentTokenAmount = bookItem.paymentTokenAmount * purchasePercent / 100;
        uint256 sellTokenAmount = bookItem.sellTokenAmount * purchasePercent / 100;

        // Checking buyer's allowance and balance for the payment token.
        uint256 buyerAllowance = IERC20(bookItem.paymentTokenAddress).allowance(msg.sender, address(this));
        if (buyerAllowance < paymentTokenAmount) revert InsufficientAllowanceOfBuyer(buyerAllowance, paymentTokenAmount);
        uint256 buyerBalance = IERC20(bookItem.paymentTokenAddress).balanceOf(msg.sender);
        if (buyerBalance < paymentTokenAmount) revert InsufficientBalanceOfBuyer(buyerBalance, paymentTokenAmount);

        // Checking seller's allowance and balance for the sell token.
        uint256 sellerAllowance = IERC20(bookItem.sellTokenAddress).allowance(bookItem.seller, address(this));
        if (sellerAllowance < sellTokenAmount) revert InsufficientAllowanceOfSeller(sellerAllowance, sellTokenAmount);
        uint256 sellerBalance = IERC20(bookItem.sellTokenAddress).balanceOf(bookItem.seller);
        if (sellerBalance < sellTokenAmount) revert InsufficientAmountOfSeller(sellerBalance, sellTokenAmount);

        // Update the book listing status or adjust the remaining amount.
        if (purchasePercent == 100) {
            bookList[bookId].isActive = false;
        } else {
            bookList[bookId].paymentTokenAmount -= paymentTokenAmount;
            bookList[bookId].sellTokenAmount -= sellTokenAmount;
        }

        // Executing the token transfers.
        IERC20(bookItem.sellTokenAddress).safeTransferFrom(bookItem.seller, msg.sender, sellTokenAmount);

        // Calculating and transferring the fee.
        uint256 fee = _calculateFee(bookItem.paymentTokenAddress, bookItem.sellTokenAddress, paymentTokenAmount);
        IERC20(bookItem.paymentTokenAddress).safeTransferFrom(msg.sender, feeWallet, fee);

        // Transferring the remaining amount to the seller.
        uint256 amountToSeller = paymentTokenAmount - fee;
        IERC20(bookItem.paymentTokenAddress).safeTransferFrom(msg.sender, bookItem.seller, amountToSeller);

        // Emitting an event for the token purchase.
        emit TokenPurchased(bookId, msg.sender);
    }

    // Function to remove a book listing.
    function removeBook(uint256 bookId) external {
        // Fetching the book item and validating its existence and seller identity.
        Book memory bookItem = bookList[bookId];
        if (bookItem.sellTokenAddress == address(0)) revert ListingDoesNotExist(bookId);
        if (msg.sender != bookItem.seller) revert OnlyTheSellerCanRemoveTheBook(bookItem.seller, msg.sender);

        // Deactivating the book listing.
        bookList[bookId].isActive = false;

        // Emitting an event for the removal of the book.
        emit BookRemoved(bookId);
    }

    // Function to update the fee rate for a specific token (referred to as a "friend token").
    function updateFriendToken(address tokenAddress, uint8 feeRate) external onlyOwner {
        // Validate that the token address is not the zero address.
        if (tokenAddress == address(0)) revert InvalidFriendTokenAddress(tokenAddress);
        // Validate that the fee rate is not greater than 100%.
        if (feeRate > 100) revert InvalidFeeRate(feeRate);

        // Update the fee rate for the specified token in the friendTokenFeeList mapping.
        friendTokenFeeList[tokenAddress] = feeRate;

        // Emit an event indicating that the fee rate for a friend token has been updated.
        emit FriendTokenUpdated(tokenAddress, feeRate);
    }

    // Function to update the address of the wallet where fees are collected.
    function updateFeeWallet(address walletAddress) external onlyOwner {
        // Validate that the wallet address is not the zero address.
        if (walletAddress == address(0)) revert InvalidFeeWalletAddress(walletAddress);

        // Update the fee wallet address.
        feeWallet = walletAddress;

        // Emit an event indicating that the fee wallet address has been updated.
        emit FeeWalletAddressUpdated(walletAddress);
    }

    // Internal function to calculate the fee amount for a transaction.
    function _calculateFee(address paymentTokenAddress, address sellTokenAddress, uint256 paymentTokenAmount) internal view returns (uint256) {
        // Start with a base fee of 3% of the payment token amount.
        uint256 fee = paymentTokenAmount * 3 / 100;

        // Apply discount based on the fee rate of the payment token if it's a friend token.
        // This reduces the fee by the percentage specified in the friendTokenFeeList.
        fee = fee * (100 - friendTokenFeeList[paymentTokenAddress]) / 100;

        // Similarly, apply discount based on the fee rate of the sell token if it's a friend token.
        fee = fee * (100 - friendTokenFeeList[sellTokenAddress]) / 100;
        
        // Return the final calculated fee.
        return fee;
    }
}
