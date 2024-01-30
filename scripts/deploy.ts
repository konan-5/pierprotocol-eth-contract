import { ethers } from "hardhat";

async function main() {
  const feeWallet = "0x2338Ba3dB74F217b92dBE82f9bf4685503B24fC9";
  const pierMarketplace = await ethers.deployContract("PierMarketplace", [feeWallet]);
  await pierMarketplace.waitForDeployment();
  console.log(
    `PierMarketplace deployed to ${pierMarketplace.target}`
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
