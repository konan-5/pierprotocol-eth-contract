// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Importing necessary OpenZeppelin contracts for token interface, ownership, security, and safe token operations.
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// PierMarketplace contract inheriting from Ownable and ReentrancyGuard for ownership management and reentrancy protection.
contract PierMarketplace is Ownable, ReentrancyGuard {
    // SafeERC20 library usage for safe token operations.
    using SafeERC20 for IERC20;

    // Book struct to hold details about a listing in the marketplace.
    struct Book {
        address seller;
        address sellTokenAddress;
        uint256 sellTokenAmount;
        address paymentTokenAddress;
        uint256 paymentTokenAmount;
        bool isActive;
    }

    // Struct to hold details about listings priced in ETH.
    struct BookForETH {
        address seller;
        address sellTokenAddress;
        uint256 sellTokenAmount;
        uint256 ETHAmount;
        bool isActive;
    }

    // State variables to track counts of different listing types and friend tokens.
    uint256 public bookCount = 0;
    uint256 public bookForETHCount = 0;
    address public feeWallet;

    // Mappings for different types of listings and friend tokens.
    mapping(uint256 => Book) public bookList;
    mapping(address => uint8) public friendTokenFeeList;

    // Events to log various actions and changes on the contract.
    event Booked(uint256 indexed bookId, address indexed seller, address indexed sellTokenAddress, uint256 sellTokenAmount, address paymentTokenAddress, uint256 paymentTokenAmount);
    event TokenPurchased(uint256 indexed bookId, address indexed buyer);
    event BookRemoved(uint256 indexed bookId);
    event FriendTokenUpdated(address indexed tokenAddress, uint256 indexed feeRate);
    event FeeWalletAddressUpdated(address indexed feeWallet);

    // Custom errors for handling specific fail conditions.
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

    // Constructor to set the fee wallet address on deployment.
    constructor(address _feeWallet) Ownable(msg.sender) {
        feeWallet = _feeWallet;
    }

    // Function to list a token for sale in exchange for another token.
    function book(address sellTokenAddress, uint256 sellTokenAmount, address paymentTokenAddress, uint256 paymentTokenAmount) external nonReentrant {
        // Validation checks for the inputs.
        if (sellTokenAmount == 0) revert InvalidSellTokenAmount(sellTokenAmount);
        if (paymentTokenAmount == 0) revert InvalidPaymentTokenAmount(paymentTokenAmount);
        if (sellTokenAddress == address(0)) revert InvalidSellTokenAddress(sellTokenAddress);
        if (paymentTokenAddress == address(0)) revert InvalidPaymentTokenAddress(paymentTokenAddress);

        // Checking the allowance of the marketplace contract to handle seller's tokens.
        address sender = msg.sender;
        uint256 allowance = IERC20(sellTokenAddress).allowance(sender, address(this));
        require(allowance >= sellTokenAmount, "Marketplace does not have enough allowance to transfer tokens");

        // Adding the listing to the book list.
        bookCount++;
        bookList[bookCount] = Book(
            sender,
            sellTokenAddress,
            sellTokenAmount,
            paymentTokenAddress,
            paymentTokenAmount,
            true
        );

        // Emitting an event for the new listing.
        emit Booked(bookCount, sender, sellTokenAddress, sellTokenAmount, paymentTokenAddress, paymentTokenAmount);
    }

    // Function to buy tokens from a listing.
    function buyToken(uint256 bookId, uint256 purchasePercent) external nonReentrant {
        // Validation checks for the purchase percent.
        if (purchasePercent == 0 || purchasePercent > 100) revert InvalidPurchasePercent(purchasePercent);

        // Retrieving the book item and performing checks.
        Book memory bookItem = bookList[bookId];
        if (bookItem.paymentTokenAddress == address(0)) revert ListingDoesNotExist(bookId);
        if (!bookItem.isActive) revert ListingDoesNotExist(bookId);

        // Calculating the amount of tokens to be transferred based on the purchase percent.
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

        // Updating the book item's status or amounts based on the purchase percent.
        if (purchasePercent == 100) {
            bookList[bookId].isActive = false;
        } else {
            bookList[bookId].paymentTokenAmount -= paymentTokenAmount;
            bookList[bookId].sellTokenAmount -= sellTokenAmount;
        }

        // Transferring the sell token from the seller to the buyer.
        IERC20(bookItem.sellTokenAddress).safeTransferFrom(bookItem.seller, msg.sender, sellTokenAmount);

        // Calculating and transferring the fee to the fee wallet.
        uint256 fee = _calculateFee(bookItem.paymentTokenAddress, bookItem.sellTokenAddress, paymentTokenAmount);
        IERC20(bookItem.paymentTokenAddress).safeTransferFrom(msg.sender, feeWallet, fee);

        // Transferring the remaining payment amount to the seller.
        uint256 amountToSeller = paymentTokenAmount - fee;
        IERC20(bookItem.paymentTokenAddress).safeTransferFrom(msg.sender, bookItem.seller, amountToSeller);

        // Emitting an event for the token purchase.
        emit TokenPurchased(bookId, msg.sender);
    }

    // Function to remove a book (listing) from the marketplace.
    function removeBook(uint256 bookId) external {
        // Retrieving the book item and checking if the sender is the seller.
        Book memory bookItem = bookList[bookId];
        if (bookItem.sellTokenAddress == address(0)) revert ListingDoesNotExist(bookId);
        if (msg.sender != bookItem.seller) revert OnlyTheSellerCanRemoveTheBook(bookItem.seller, msg.sender);

        // Marking the book as inactive.
        bookList[bookId].isActive = false;

        // Emitting an event for the book removal.
        emit BookRemoved(bookId);
    }

    // Function for the owner to add a friend token with a specific fee rate.
    function updateFriendToken(address tokenAddress, uint8 feeRate) external onlyOwner {
        // Validation checks for the token address and fee rate.
        if (tokenAddress == address(0)) revert InvalidFriendTokenAddress(tokenAddress);
        if (feeRate > 100) revert InvalidFeeRate(feeRate);

        // Adding the friend token to the list.
        friendTokenFeeList[tokenAddress] = feeRate;

        // Emitting an event for the new friend token.
        emit FriendTokenUpdated(tokenAddress, feeRate);
    }

    // Function to update the fee wallet address, restricted to the contract owner.
    function updateFeeWallet(address walletAddress) external onlyOwner {
        // Validate the new wallet address.
        if (walletAddress == address(0)) revert InvalidFeeWalletAddress(walletAddress);

        // Update the fee wallet address.
        feeWallet = walletAddress;

        // Emit an event to log the update of the fee wallet address.
        emit FeeWalletAddressUpdated(walletAddress);
    }

    // Internal function to calculate the fee for a transaction.
    function _calculateFee(address paymentTokenAddress, address sellTokenAddress, uint256 paymentTokenAmount) internal view returns (uint256) {
        // Start with a base fee calculation: 3% of the payment token amount.
        uint256 fee = paymentTokenAmount * 3 / 100;

        fee = fee * (100 - friendTokenFeeList[paymentTokenAddress]) / 100;
        fee = fee * (100 - friendTokenFeeList[sellTokenAddress]) / 100;
        
        return fee;
    }
}
