import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
const dotenv = require('dotenv');

dotenv.config()

const privateKey = process.env.PRIVATE_KEY ? process.env.PRIVATE_KEY : "";

const config: HardhatUserConfig = {
  solidity: "0.8.20",
  networks: {
    ftmtest: {
      url: "https://rpc.testnet.fantom.network",
      accounts: [privateKey]
    },
    eth: {
      url: "https://rpc.mevblocker.io",
      accounts: [privateKey]
    }
  }
};

export default config;
