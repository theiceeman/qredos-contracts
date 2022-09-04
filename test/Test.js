const { expect } = require("chai");
const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

describe("Qredos", function () {
  before(async () => {
    [deployer, buyer, lender, liquidator] = await ethers.getSigners();

    weth = await ethers.getContractFactory("ERC20Token");
    WETH = await weth.deploy("Wrapped Ether", "WETH");

    PoolRegistryStore = await ethers.getContractFactory("PoolRegistryStore");
    poolRegistryStore = await PoolRegistryStore.deploy();
    PoolRegistry = await ethers.getContractFactory("PoolRegistry");
    poolRegistry = await PoolRegistry.deploy(
      WETH.address,
      poolRegistryStore.address
    );
    Qredos = await ethers.getContractFactory("Qredos");
    qredos = await Qredos.deploy(WETH.address, poolRegistry.address);
  });
  describe("createPool", function () {
    it("test", async () => {
      console.log(qredos);
    });
  });
});
