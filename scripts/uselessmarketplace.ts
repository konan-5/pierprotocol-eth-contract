import { ethers } from "hardhat";

async function main() {
  const currentTimestampInSeconds = Math.round(Date.now() / 1000);
  const unlockTime = currentTimestampInSeconds + 60;

  const lockedAmount = ethers.parseEther("0.001");

  const uselessMarketplace = await ethers.getContractAt("UselessMarketplace", "0x304fc982dA58D1290E314F1Dc96C66316fA32638")
  const wethAddress = await uselessMarketplace.WETH()
  console.log(wethAddress)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
