require("@nomicfoundation/hardhat-toolbox");
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("./tasks/PrintAccounts");
// require("@nomiclabs/hardhat-etherscan");
// require("hardhat-gas-reporter");

const dotenv = require('dotenv')
dotenv.config()
// require("hardhat-gas-reporter");

const PRIVATE_KEY_1 = process.env.PRIVATE_KEY;
const PRIVATE_KEY_2 = process.env.PRIVATE_KEY_2;

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      blockGasLimit: 12000000,
      allowUnlimitedContractSize: true,
    },
    goerli: {
      url: process.env.GOERLI_RPC,
      accounts: [PRIVATE_KEY_1,PRIVATE_KEY_2]
    },
    mumbai: {
      url: process.env.MUMBAI_RPC,
      accounts: [PRIVATE_KEY_1,PRIVATE_KEY_2],
      timeout: 1200000 // set timeout to 60 seconds
    }
    /* rinkeby: {
      url: "https://eth-rinkeby.alchemyapi.io/v2/123abc123abc123abc123abc123abcde",
      accounts: [privateKey1, privateKey2, ...]
    } */
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    // apiKey: BSCSCAN_API_KEY,
  },
  solidity: {
    compilers: [
      {
        version: "0.8.1",
      },
      {
        version: "0.8.9",
      },
    ],
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      maxCodeSize: 60000000
    },
  },
  gasPrice: 1000000000, // 1 gwei
  mocha: {
    timeout: 20000,
  },
  gasReporter: {
    enabled: true,
  },
};
