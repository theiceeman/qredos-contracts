const { expect } = require("chai");
const { BigNumber, providers } = require("ethers");
const { parseEther } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

describe("Qredos", function () {
  let POOL_ID, PURCHASE_ID;
  before(async () => {
    [deployer, buyer, lender, liquidator] = await ethers.getSigners();

    weth = await ethers.getContractFactory("ERC20Token");
    WETH = await weth.deploy("Wrapped Ether", "WETH");

    bayc = await ethers.getContractFactory("ERC721Token");
    BAYC = await bayc.deploy();
    BAYC.safeMint(deployer.address, 0);

    PoolRegistryStore = await ethers.getContractFactory("PoolRegistryStore");
    poolRegistryStore = await PoolRegistryStore.deploy();
    QredosStore = await ethers.getContractFactory("QredosStore");
    qredosStore = await QredosStore.deploy();
    // Pool
    PoolRegistry = await ethers.getContractFactory("PoolRegistry");
    poolRegistry = await PoolRegistry.deploy(
      WETH.address,
      poolRegistryStore.address
    );
    // Oracle
    Qredos = await ethers.getContractFactory("Qredos");
    qredos = await Qredos.deploy(
      WETH.address,
      poolRegistry.address,
      qredosStore.address
    );

    // Transfer pool ownership to oracle
    await poolRegistry.transferOwnership(qredos.address);
    // Transfer pool store ownership to pool
    await poolRegistryStore.transferOwnership(poolRegistry.address);
    // Transfer qredos store ownership to oracle
    await qredosStore.transferOwnership(qredos.address);

    // Fund test accounts with accepted payment token
    await WETH.transfer(buyer.address, parseEther("50000"));
    await WETH.transfer(lender.address, parseEther("50000"));
    await WETH.transfer(liquidator.address, parseEther("50000"));
  });
  describe("createPool", function () {
    it("should emit poolFunded & poolCreated events if successfull", async () => {
      let amount = parseEther("5000"); // 50000

      await WETH.connect(lender).approve(qredos.address, amount);
      let txn = await qredos
        .connect(lender)
        .createPool(amount, 3, 30, 7890000, 3, lender.address);
      let reciept = await txn.wait();
      let PoolCreatedEvent = reciept.events?.filter((x) => {
        return x.event == "PoolCreated";
      });
      POOL_ID = PoolCreatedEvent[0].args.poolId;

      expect(reciept).to.emit(PoolRegistry, "PoolCreated");
      expect(reciept).to.emit(PoolRegistry, "PoolFunded");
    });
    it("should increase pool balance if successfull", async () => {
      let expectedPoolBalance = parseEther("5000");
      let result = await qredos.getPoolBalance(POOL_ID);
      expect(result).to.equal(expectedPoolBalance);
    });
  });
  describe("fundPool", function () {
    it("should fail with an invalid poolId", async () => {
      let amount = parseEther("2500");

      await WETH.connect(lender).approve(qredos.address, amount);
      await expect(
        qredos.connect(lender).fundPool(2, amount)
      ).to.be.revertedWith("getPoolByID: No such record");
    });
    it("should emit poolFunded event if successfull", async () => {
      let amount = parseEther("2500");

      await WETH.connect(lender).approve(qredos.address, amount);
      let txn = await qredos.connect(lender).fundPool(POOL_ID, amount);
      let reciept = await txn.wait();
      expect(reciept).to.emit(PoolRegistry, "PoolFunded");
    });
    it("should increase pool balance if successfull", async () => {
      let expectedPoolBalance = parseEther("7500");
      let result = await qredos.getPoolBalance(POOL_ID);
      expect(result).to.equal(expectedPoolBalance);
    });
  });
  describe("purchaseNFT", async function () {
    it("should fail with an invalid poolId", async () => {
      let downPaymentAmount = parseEther("10000");
      let principal = parseEther("10000");
      let invalidPooliD = 2;

      await expect(
        qredos
          .connect(buyer)
          .purchaseNFT(
            BAYC.address,
            0,
            downPaymentAmount,
            principal,
            invalidPooliD
          )
      ).to.be.revertedWith("getPoolByID: No such record");
    });
    it("should fail with invalid principal", async () => {
      let downPaymentAmount = parseEther("10000");
      let invalidPrincipal = parseEther("700");

      await expect(
        qredos
          .connect(buyer)
          .purchaseNFT(
            BAYC.address,
            0,
            downPaymentAmount,
            invalidPrincipal,
            POOL_ID
          )
      ).to.be.revertedWith("Qredos.purchaseNFT: Invalid principal!");
    });
    it("should fail if pool has insufficient funds", async () => {
      let downPaymentAmount = parseEther("100000");
      let invalidPrincipal = parseEther("100000");

      await expect(
        qredos
          .connect(buyer)
          .purchaseNFT(
            BAYC.address,
            0,
            downPaymentAmount,
            invalidPrincipal,
            POOL_ID
          )
      ).to.be.revertedWith(
        "Qredos.purchaseNFT: Selected pool can't fund purchase!"
      );
    });
    it("should emit PurchaseCreated event if successfull", async () => {
      let downPaymentAmount = parseEther("2000");
      let invalidPrincipal = parseEther("2000");
      await WETH.connect(buyer).approve(qredos.address, downPaymentAmount);
      let txn = await qredos
        .connect(buyer)
        .purchaseNFT(
          BAYC.address,
          0,
          downPaymentAmount,
          invalidPrincipal,
          POOL_ID
        );
      let result = await txn.wait();

      let PoolCreatedEvent = result.events?.filter((x) => {
        return x.event == "PurchaseCreated";
      });
      PURCHASE_ID = PoolCreatedEvent[0].args.purchaseId;

      expect(result).to.emit(qredos, "PurchaseCreated");
    });
  });

  describe("completeNFTPurchase", async function () {
    it("should fail with invalid purchaseId", async () => {
      let invalidPurchaseId = 10;
      await expect(
        qredos.connect(buyer).completeNFTPurchase(invalidPurchaseId)
      ).to.be.revertedWith("No such record");
    });
    it("should fail if oracle does not own nft", async () => {
      await expect(
        qredos.connect(buyer).completeNFTPurchase(PURCHASE_ID)
      ).to.be.revertedWith("Qredos: Purchase Incomplete!");

      // Tranfer token to oracle.
      // await BAYC.safeTransferFrom(deployer.address, qredos.address, 0);
      await BAYC["safeTransferFrom(address,address,uint256)"](
        deployer.address,
        qredos.address,
        0
      );
    });
    // it("should fail if oracle does not own escrow", async () => {
    //   await expect(
    //     qredos.connect(buyer).completeNFTPurchase(PURCHASE_ID)
    //   ).to.be.revertedWith("Qredos: Purchase Incomplete!");
    // });
  });
});
