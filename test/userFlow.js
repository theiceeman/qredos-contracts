const { expect } = require("chai");
const { BigNumber, providers } = require("ethers");
const { parseEther, formatEther } = require("ethers/lib/utils");
const { ethers } = require("hardhat");
const { increaseTimeTo, latestTime, duration } = require("./utils/utils");

describe("Qredos", function () {
  let POOL_ID;

  before(async () => {
    provider = ethers.provider;
    [deployer, buyer, lender, liquidator, tester] = await ethers.getSigners();

    // UTILITIES
    // weth = await ethers.getContractFactory("ERC20Token");
    // WETH = await weth.deploy("Wrapped Ether", "WETH");

    bayc = await ethers.getContractFactory("ERC721Token");
    BAYC = await bayc.deploy();
    BAYC.safeMint(deployer.address, 0);

    // CONTRACTS
    PoolRegistryStore = await ethers.getContractFactory("PoolRegistryStore");
    poolRegistryStore = await PoolRegistryStore.deploy();
    QredosStore = await ethers.getContractFactory("QredosStore");
    qredosStore = await QredosStore.deploy();
    // Pool
    PoolRegistry = await ethers.getContractFactory("PoolRegistry");
    poolRegistry = await PoolRegistry.deploy(
      // WETH.address,
      poolRegistryStore.address
    );
    // Oracle
    Qredos = await ethers.getContractFactory("Qredos");
    qredos = await Qredos.deploy(
      // WETH.address,
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
    // await WETH.transfer(buyer.address, parseEther("50000"));
    // await WETH.transfer(lender.address, parseEther("50000"));
    // await WETH.transfer(liquidator.address, parseEther("50000"));

    await tester.sendTransaction({
      to: lender.address,
      value: parseEther("9999"),
    });

    // CREATE POOL
    let amount = parseEther("10000");
    let paymentCycle = 2;
    let APR = 5;
    let durationInSecs = 5260000;
    let durationInMonths = 2;

    // await WETH.connect(lender).approve(qredos.address, amount);
    let txn = await qredos
      .connect(lender)
      .createPool(
        amount,
        paymentCycle,
        APR,
        durationInSecs,
        durationInMonths,
        lender.address,
        { value: amount }
      );
    let reciept = await txn.wait();
    let PoolCreatedEvent = reciept.events?.filter((x) => {
      return x.event == "PoolCreated";
    });
    POOL_ID = PoolCreatedEvent[0].args.poolId;
  });

  describe("scenario 1: smooth transaction", function () {
    it("qredos should collect 1,050 after 2 months", async () => {
      let downPaymentAmount = parseEther("1000");
      let principal = parseEther("1000");
      let tokenId = 0;
      // purchase nft
      let PURCHASE_ID = await purchaseNFT(
        downPaymentAmount,
        principal,
        tokenId,
        POOL_ID
      );
      // complete nft purchase
      await BAYC["safeTransferFrom(address,address,uint256)"](
        deployer.address,
        qredos.address,
        tokenId
      );
      await qredos.connect(buyer).completeNFTPurchase(PURCHASE_ID);
      // let poolBalanceBefore = await WETH.balanceOf(poolRegistry.address);
      let poolBalanceBefore = await provider.getBalance(poolRegistry.address);

      //   make first part payment
      let PART = BigNumber.from("1");
      // await WETH.connect(buyer).approve(qredos.address, principal);
      await qredos.connect(buyer).repayLoan(PURCHASE_ID, PART, POOL_ID, { value: principal });

      //   Before the two months period ends
      await increaseTimeTo((await latestTime()) + duration.weeks(7));

      //   Make second part payment
      // await WETH.connect(buyer).approve(qredos.address, principal);
      await qredos.connect(buyer).repayLoan(PURCHASE_ID, PART, POOL_ID, { value: principal });

      // let poolBalanceAfter = await WETH.balanceOf(poolRegistry.address);
      let poolBalanceAfter = await provider.getBalance(poolRegistry.address);

      expect(
        formatEther(poolBalanceAfter) - formatEther(poolBalanceBefore)
      ).to.be.equal(1050);
    });
  });

  describe("Default on first month", function () {
    it("user pays before liquidation: qredos should collect 700 (partPayment + default fee + interest)", async () => {
      let downPaymentAmount = parseEther("1000");
      let principal = parseEther("1000");
      let tokenId = 1;
      BAYC.safeMint(deployer.address, tokenId);
      // purchase nft
      let PURCHASE_ID = await purchaseNFT(
        downPaymentAmount,
        principal,
        tokenId,
        POOL_ID
      );
      // complete nft purchase
      await BAYC["safeTransferFrom(address,address,uint256)"](
        deployer.address,
        qredos.address,
        tokenId
      );
      await qredos.connect(buyer).completeNFTPurchase(PURCHASE_ID);
      // let poolBalanceBefore = await WETH.balanceOf(poolRegistry.address);
      let poolBalanceBefore = await provider.getBalance(poolRegistry.address);

      // one month period ends
      await increaseTimeTo((await latestTime()) + duration.weeks(5));

      let PART = BigNumber.from("1");
      // await WETH.connect(buyer).approve(qredos.address, principal);
      await qredos.connect(buyer).repayLoan(PURCHASE_ID, PART, POOL_ID, { value: principal });

      // let poolBalanceAfter = await WETH.balanceOf(poolRegistry.address);
      let poolBalanceAfter = await provider.getBalance(poolRegistry.address);

      expect(
        formatEther(poolBalanceAfter) - formatEther(poolBalanceBefore)
      ).to.be.equal(700);
    });

    it("after liquidation: QREDOS COLLECTS 1150 (MONEY LENT + DEFAULT FEE)", async () => {
      let downPaymentAmount = parseEther("1000");
      let principal = parseEther("1000");
      let tokenId = 2;
      BAYC.safeMint(deployer.address, tokenId);
      // purchase nft
      let PURCHASE_ID = await purchaseNFT(
        downPaymentAmount,
        principal,
        tokenId,
        POOL_ID
      );
      // complete nft purchase
      await BAYC["safeTransferFrom(address,address,uint256)"](
        deployer.address,
        qredos.address,
        tokenId
      );
      await qredos.connect(buyer).completeNFTPurchase(PURCHASE_ID);
      // let poolBalanceBefore = await WETH.balanceOf(poolRegistry.address);
      let poolBalanceBefore = await provider.getBalance(poolRegistry.address);

      // one month period ends
      await increaseTimeTo((await latestTime()) + duration.weeks(5));

      let liquidationAmount = parseEther("1150");
      let currentNftPrice = parseEther("2000");
      // await WETH.connect(liquidator).approve(qredos.address, liquidationAmount);
      let LIQUIDATION_ID = await startLiquidation(
        liquidationAmount,
        PURCHASE_ID,
        currentNftPrice, buyer.address
      );
      // complete liquidation
      await qredos
        .connect(liquidator)
        .completeLiquidation(LIQUIDATION_ID, buyer.address, { value: liquidationAmount });

      // let poolBalanceAfter = await WETH.balanceOf(poolRegistry.address);
      let poolBalanceAfter = await provider.getBalance(poolRegistry.address);

      expect(
        formatEther(poolBalanceAfter) - formatEther(poolBalanceBefore)
      ).to.be.equal(1150);
    });
  });

  describe("Default on second month", function () {
    it("after liquidation: qredos collects 1200 (principal + default fee + interest)", async () => {
      let downPaymentAmount = parseEther("1000");
      let principal = parseEther("1000");
      let tokenId = 3;
      BAYC.safeMint(deployer.address, tokenId);
      // purchase nft
      let PURCHASE_ID = await purchaseNFT(
        downPaymentAmount,
        principal,
        tokenId,
        POOL_ID
      );
      // complete nft purchase
      await BAYC["safeTransferFrom(address,address,uint256)"](
        deployer.address,
        qredos.address,
        tokenId
      );
      await qredos.connect(buyer).completeNFTPurchase(PURCHASE_ID);

      // first part payment
      let PART = BigNumber.from("1");
      // await WETH.connect(buyer).approve(qredos.address, principal);
      await qredos.connect(buyer).repayLoan(PURCHASE_ID, PART, POOL_ID, { value: principal });

      // forward time to second month
      await increaseTimeTo((await latestTime()) + duration.weeks(9));

      // let poolBalanceBefore = await WETH.balanceOf(poolRegistry.address);
      let poolBalanceBefore = await provider.getBalance(poolRegistry.address);

      // LIQUIDATE NFT
      let liquidationAmount = parseEther("2050");
      let currentNftPrice = parseEther("2000");
      // await WETH.connect(liquidator).approve(qredos.address, liquidationAmount);
      let LIQUIDATION_ID = await startLiquidation(
        liquidationAmount,
        PURCHASE_ID,
        currentNftPrice,
        buyer.address,
        { value: liquidationAmount }
      );
      // complete liquidation
      await qredos
        .connect(liquidator)
        .completeLiquidation(LIQUIDATION_ID, buyer.address,{value:liquidationAmount});

      // let poolBalanceAfter = await WETH.balanceOf(poolRegistry.address);
      let poolBalanceAfter = await provider.getBalance(poolRegistry.address);

      // let buyerBalanceBefore = await WETH.balanceOf(buyer.address);
      let buyerBalanceBefore = await provider.getBalance(buyer.address);
      await qredos.connect(buyer).refundBorrower(PURCHASE_ID, LIQUIDATION_ID);
      // let buyerBalanceAfter = await WETH.balanceOf(buyer.address);
      let buyerBalanceAfter = await provider.getBalance(buyer.address);

      // we get 2050 weth when liquidation is completed
      expect(
        formatEther(poolBalanceAfter) - formatEther(poolBalanceBefore)
      ).to.be.equal(2050);
      // user gets their 1375 weth
      expect(
        formatEther(buyerBalanceAfter) - formatEther(buyerBalanceBefore)
      ).to.be.equal(1375);
    });
  });

  describe("REDUCED NFT PRICE / VALUE BELOW 10%", function () {
    it("nft is liquidated before first month is completed", async () => {
      let downPaymentAmount = parseEther("1000");
      let principal = parseEther("1000");
      let tokenId = 4;
      BAYC.safeMint(deployer.address, tokenId);
      // purchase nft
      let PURCHASE_ID = await purchaseNFT(
        downPaymentAmount,
        principal,
        tokenId,
        POOL_ID
      );
      // complete nft purchase
      await BAYC["safeTransferFrom(address,address,uint256)"](
        deployer.address,
        qredos.address,
        tokenId
      );
      await qredos.connect(buyer).completeNFTPurchase(PURCHASE_ID);

      // let poolBalanceBefore = await WETH.balanceOf(poolRegistry.address);
      let poolBalanceBefore = await provider.getBalance(poolRegistry.address);

      // LIQUIDATE NFT
      let liquidationAmount = parseEther("2050");
      let currentNftPrice = parseEther("1800");
      // await WETH.connect(liquidator).approve(qredos.address, liquidationAmount);
      let LIQUIDATION_ID = await startLiquidation(
        liquidationAmount,
        PURCHASE_ID,
        currentNftPrice,
        buyer.address
      );
      // complete liquidation
      await qredos
        .connect(liquidator)
        .completeLiquidation(LIQUIDATION_ID, buyer.address,{value:liquidationAmount});

      // let poolBalanceAfter = await WETH.balanceOf(poolRegistry.address);
      let poolBalanceAfter = await provider.getBalance(poolRegistry.address);

      // let buyerBalanceBefore = await WETH.balanceOf(buyer.address);
      let buyerBalanceBefore = await provider.getBalance(buyer.address);

      await qredos.connect(buyer).refundBorrower(PURCHASE_ID, LIQUIDATION_ID);
      // let buyerBalanceAfter = await WETH.balanceOf(buyer.address);
      let buyerBalanceAfter = await provider.getBalance(buyer.address);

      // we get 2050 weth when liquidation is completed
      expect(
        formatEther(poolBalanceAfter) - formatEther(poolBalanceBefore)
      ).to.be.equal(2050);
      // user gets their 1375 weth
      expect(
        formatEther(buyerBalanceAfter) - formatEther(buyerBalanceBefore)
      ).to.be.equal(800);
    });
  });
});

async function purchaseNFT(downPaymentAmount, principal, tokenId, POOL_ID) {
  // await WETH.connect(buyer).approve(qredos.address, downPaymentAmount);
  let purchaseNftTxn = await qredos
    .connect(buyer)
    .purchaseNFT(BAYC.address, tokenId, downPaymentAmount, principal, POOL_ID, { value: downPaymentAmount });
  let purchaseNFTResult = await purchaseNftTxn.wait();
  let PurchaseCreatedEvent = purchaseNFTResult.events?.filter((x) => {
    return x.event == "PurchaseCreated";
  });
  return PurchaseCreatedEvent[0].args.purchaseId;
}

async function startLiquidation(
  discountAmount,
  PURCHASE_ID,
  currentNftPrice,
  borrowerAddress
) {
  let txn = await qredos
    .connect(deployer)
    .startLiquidation(
      PURCHASE_ID,
      discountAmount,
      currentNftPrice,
      borrowerAddress
    );
  let reciept = await txn.wait();

  let event = reciept.events?.filter((x) => {
    return x.event == "StartLiquidation";
  });
  return (LIQUIDATION_ID = event[0].args.liquidationId);
}
