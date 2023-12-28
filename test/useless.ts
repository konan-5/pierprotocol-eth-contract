import { ethers } from 'hardhat';
import { expect } from 'chai';
import { Contract, Signer } from 'ethers';

describe('PierMarketplace', function () {
  let owner: Signer;
  let addr1: Signer;
  let addr2: Signer;
  let pierToken: Contract;
  let paymentToken: Contract;
  let otherToken: Contract;
  let pierMarketplace: any;

  const provider = ethers.provider;

  beforeEach(async () => {
    [owner, addr1, addr2] = await ethers.getSigners();

    console.log(owner, addr1, addr2);
    
    // Deploy mock tokens (pierToken, paymentToken, etc.) here
    // ...

    const PierMarketplace = await ethers.getContractFactory('PierMarketplace');
    pierMarketplace = await PierMarketplace.deploy(
      "pierToken.address", 
      await owner.getAddress(), 
      await owner.getAddress(), 
      "paymentToken.address"
    );
  });

  describe('Deployment', () => {
    it('Should set the right owner', async () => {
      expect(await pierMarketplace.owner()).to.equal(await owner.getAddress());
    });

    // Additional deployment tests...
  });

  describe('listTokenForSale', () => {
    it('Should list a token for sale successfully', async () => {
      // Setup for listing a token, like minting and approving
      // ...

      await expect(pierMarketplace.connect(addr1).listTokenForSale(/* args */))
        .to.emit(pierMarketplace, 'TokenListed');
        // Check emitted event arguments
    });

    it('Should fail for zero token amount', async () => {
      // Setup
      // ...

      await expect(pierMarketplace.connect(addr1).listTokenForSale(/* args with zero amount */))
        .to.be.revertedWith('AmountMustBeGreaterThanZero');
    });

    // Additional tests for listTokenForSale...
  });

  // Tests for other functions (listTokenToBuy, buyToken, sellToken, etc.)
  // ...

});
