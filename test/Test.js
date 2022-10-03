const { expect } = require("chai");
const { BigNumber, providers } = require("ethers");
const { parseEther } = require("ethers/lib/utils");
const { ethers } = require("hardhat");
const { increaseTimeTo, latestTime, duration } = require("./utils/utils");

describe("Qredos", function () {
  let POOL_ID,
    PURCHASE_ID,
    POOL_ID_2,
    PURCHASE_ID_2,
    POOL_ID_3,
    PURCHASE_ID_3,
    LIQUIDATION_ID;

  // should emit loanRepaid event if successfull
  let lendingPoolBalanceBefore;
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

      let PurchaseCreatedEvent = result.events?.filter((x) => {
        return x.event == "PurchaseCreated";
      });
      PURCHASE_ID = PurchaseCreatedEvent[0].args.purchaseId;

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
    //   ).to.be.revertedWith("Qredos: Invalid escrow owner!");
    // });
    it("should fail if caller isnt buyer", async () => {
      await expect(
        qredos.connect(liquidator).completeNFTPurchase(PURCHASE_ID)
      ).to.be.revertedWith("No such record");
    });

    it("should emit purchaseCompleted event if successfull", async () => {
      let txn = await qredos.connect(buyer).completeNFTPurchase(PURCHASE_ID);

      let result = await txn.wait();
      expect(result).to.emit(qredos, "PurchaseCompleted");
    });

    it("should update purchaseStatus to complete if successfull", async () => {
      let purchase = await qredosStore.getPurchaseByID(
        buyer.address,
        PURCHASE_ID
      );
      expect(purchase.status).to.equal(1);
    });
  });

  describe("repayLoan(full)", async function () {
    it("should fail with invalid purchaseId", async () => {
      let invalidPurchaseId = 10;
      const FULL = BigNumber.from("0");
      await expect(
        qredos.connect(buyer).repayLoan(invalidPurchaseId, FULL, POOL_ID)
      ).to.be.revertedWith("No such record");
    });
    it("should emit loanRepaid event if successfull", async () => {
      lendingPoolBalanceBefore = await WETH.balanceOf(poolRegistry.address);
      //
      const FULL = BigNumber.from("0");
      let purchase = await qredosStore.getPurchaseByID(
        buyer.address,
        PURCHASE_ID
      );
      let loan = await poolRegistryStore.getLoanByPoolID(
        purchase.poolId,
        purchase.loanId
      );

      await WETH.connect(buyer).approve(qredos.address, loan.principal);
      let txn = await qredos
        .connect(buyer)
        .repayLoan(PURCHASE_ID, FULL, POOL_ID);
      let result = await txn.wait();
      expect(result).to.emit(qredos, "LoanRepaid");
    });
    it("should increase lending pool contract balance if successfull", async () => {
      let lendingPoolBalanceAfter = await WETH.balanceOf(poolRegistry.address);
      expect(lendingPoolBalanceAfter).to.be.greaterThan(
        lendingPoolBalanceBefore
      );
    });
    it("should set state for loanRepayment if successfull", async () => {
      let purchase = await qredosStore.getPurchaseByID(
        buyer.address,
        PURCHASE_ID
      );
      let loanRepayment = await poolRegistryStore.LoanRepayment(
        purchase.loanId,
        0
      );
      expect(loanRepayment.isExists).to.equal(true);
    });
    it("should set loan status as closed if successfull", async () => {
      let loan = await poolRegistryStore.getLoanByPoolID(POOL_ID, 0);
      expect(loan.status).to.equal(1);
    });
  });

  describe("repayLoan(part)", async function () {
    it("should increase pool contract balance & emit loanRepaid event", async () => {
      BAYC.safeMint(deployer.address, 1);
      // create new pool for this test case
      let amount = parseEther("7000"); // 50000
      await WETH.connect(lender).approve(qredos.address, amount);
      let createPoolTxn = await qredos
        .connect(lender)
        .createPool(amount, 3, 30, 7890000, 3, lender.address);
      let createPoolResult = await createPoolTxn.wait();
      let PoolCreatedEvent = createPoolResult.events?.filter((x) => {
        return x.event == "PoolCreated";
      });
      POOL_ID_2 = PoolCreatedEvent[0].args.poolId;
      // purchase another nft for this test case
      let downPaymentAmount = parseEther("3500");
      let principalAmount = parseEther("3500");

      await WETH.connect(buyer).approve(qredos.address, downPaymentAmount);
      let PurchaseTxn = await qredos
        .connect(buyer)
        .purchaseNFT(
          BAYC.address,
          1,
          downPaymentAmount,
          principalAmount,
          POOL_ID_2
        );
      let PurchaseResult = await PurchaseTxn.wait();

      let PurchaseCreatedEvent = PurchaseResult.events?.filter((x) => {
        return x.event == "PurchaseCreated";
      });
      PURCHASE_ID_2 = PurchaseCreatedEvent[0].args.purchaseId;
      // transfer token to oracle
      await BAYC["safeTransferFrom(address,address,uint256)"](
        deployer.address,
        qredos.address,
        1
      );

      let _lendingPoolBalanceBefore = await WETH.balanceOf(
        poolRegistry.address
      );

      // complete nft purchase
      await qredos.connect(buyer).completeNFTPurchase(PURCHASE_ID_2);

      // make part payment of purchase
      let PART = BigNumber.from("1");
      await WETH.connect(buyer).approve(qredos.address, principalAmount);
      let repayLoanTxn = await qredos
        .connect(buyer)
        .repayLoan(PURCHASE_ID_2, PART, POOL_ID_2);
      let repayLoanResult = await repayLoanTxn.wait();
      expect(repayLoanResult).to.emit(qredos, "LoanRepaid");

      let _lendingPoolBalanceAfter = await WETH.balanceOf(poolRegistry.address);
      expect(_lendingPoolBalanceAfter).to.be.greaterThan(
        _lendingPoolBalanceBefore
      );
    });

    it("should set state for loan part payment", async () => {
      let loanRepayment = await poolRegistryStore.getLoanRepaymentByLoanID(
        1,
        0
      );
      expect(loanRepayment?.isExists).to.be.equal(true);
    });

    it("should complete the part payments, then check if loan status is closed", async () => {
      let PART = BigNumber.from("1");
      let principalAmount = parseEther("3500");
      let loan = await poolRegistryStore.getLoanByPoolID(POOL_ID_2, 1);
      expect(loan.status).to.be.equal(0);

      await WETH.connect(buyer).approve(qredos.address, principalAmount);
      await qredos.connect(buyer).repayLoan(PURCHASE_ID_2, PART, POOL_ID_2);
      await WETH.connect(buyer).approve(qredos.address, principalAmount);
      await qredos.connect(buyer).repayLoan(PURCHASE_ID_2, PART, POOL_ID_2);

      loan = await poolRegistryStore.getLoanByPoolID(POOL_ID_2, 1);
      expect(loan.status).to.be.equal(1);
    });
  });

  describe("claimNft", async function () {
    it("should fail if invalid purchaseId", async () => {
      let invalidPurchaseId = 10;
      await expect(
        qredos.connect(buyer).claimNft(invalidPurchaseId, POOL_ID_2)
      ).to.be.revertedWith("No such record");
    });
    it("should emit NFTClaimed event if successfull", async () => {
      let txn = await qredos.connect(buyer).claimNft(PURCHASE_ID_2, POOL_ID_2);
      let reciept = await txn.wait();
      expect(reciept).to.emit(qredos, "NFTClaimed");
    });
    it("buyer should own NFT if successfull", async () => {
      let result = await BAYC.ownerOf(1);
      expect(result).to.be.equal(buyer.address);
    });
    it("should update escrow status if successfull", async () => {
      let purchase = await qredosStore.getPurchaseByID(
        buyer.address,
        PURCHASE_ID_2
      );
      let escrow = await ethers.getContractAt("Escrow", purchase.escrowAddress);
      expect(await escrow.status()).to.be.equal(1);
    });
  });

  describe("startLiquidation", async function () {
    it("should purchase new nft for this test case", async () => {
      let tokenId = 2;
      BAYC.safeMint(deployer.address, tokenId);
      // create new pool for this test case
      let amount = parseEther("7000"); // 50000
      await WETH.connect(lender).approve(qredos.address, amount);
      let createPoolTxn = await qredos
        .connect(lender)
        .createPool(amount, 3, 30, 7890000, 3, lender.address);
      let createPoolResult = await createPoolTxn.wait();
      let PoolCreatedEvent = createPoolResult.events?.filter((x) => {
        return x.event == "PoolCreated";
      });
      POOL_ID_3 = PoolCreatedEvent[0].args.poolId;
      // purchase another nft for this test case
      let downPaymentAmount = parseEther("3500");
      let principalAmount = parseEther("3500");

      await WETH.connect(buyer).approve(qredos.address, downPaymentAmount);
      let PurchaseTxn = await qredos
        .connect(buyer)
        .purchaseNFT(
          BAYC.address,
          tokenId,
          downPaymentAmount,
          principalAmount,
          POOL_ID_3
        );
      let PurchaseResult = await PurchaseTxn.wait();

      let PurchaseCreatedEvent = PurchaseResult.events?.filter((x) => {
        return x.event == "PurchaseCreated";
      });
      PURCHASE_ID_3 = PurchaseCreatedEvent[0].args.purchaseId;
      // transfer token to oracle
      await BAYC["safeTransferFrom(address,address,uint256)"](
        deployer.address,
        qredos.address,
        tokenId
      );

      // complete nft purchase
      await qredos.connect(buyer).completeNFTPurchase(PURCHASE_ID_3);
    });
    it("should fail if caller isnt owner", async () => {
      let invalidPurchaseId = 10;
      let currentNftPrice = parseEther("2000");
      let discountAmount = parseEther("3000"); //  from 3500
      await expect(
        qredos
          .connect(buyer)
          .startLiquidation(
            invalidPurchaseId,
            discountAmount,
            currentNftPrice,
            buyer.address
          )
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });
    it("should fail for invalid purchaseId", async () => {
      let invalidPurchaseId = 10;
      let currentNftPrice = parseEther("2000");
      let discountAmount = parseEther("3000"); //  from 3500
      await expect(
        qredos
          .connect(deployer)
          .startLiquidation(
            invalidPurchaseId,
            discountAmount,
            currentNftPrice,
            buyer.address
          )
      ).to.be.revertedWith("No such record");
    });
    // Does not have to be defaulted
    // it("should fail if loan isnt defaulted", async () => {
    //   let discountAmount = parseEther("3000"); //  from 3500
    //   let currentNftPrice = parseEther("2000");
    //   await expect(
    //     qredos
    //       .connect(deployer)
    //       .startLiquidation(PURCHASE_ID_3, discountAmount, currentNftPrice,buyer.address)
    //   ).to.be.revertedWith("Qredos.startLiquidation: loan is not defaulted!");
    // });
    it("should emit StartLiquidation event if successfull", async () => {
      let pool = await poolRegistryStore.getPoolByID(POOL_ID_3);
      await increaseTimeTo(
        (await latestTime()) + Number(pool.durationInSecs) + duration.hours(2)
      );
      let discountAmount = parseEther("3000"); //  from 3500
      let currentNftPrice = parseEther("3000");
      let txn = await qredos
        .connect(deployer)
        .startLiquidation(
          PURCHASE_ID_3,
          discountAmount,
          currentNftPrice,
          buyer.address
        );
      let reciept = await txn.wait();

      let event = reciept.events?.filter((x) => {
        return x.event == "StartLiquidation";
      });
      LIQUIDATION_ID = event[0].args.liquidationId;
      expect(reciept).to.emit(qredos, "StartLiquidation");
    });
    it("should set liquidation state", async () => {
      let liquidation = await qredosStore.getLiquidationByID(LIQUIDATION_ID);
      expect(liquidation.isExists).to.be.equal(true);
    });
  });

  describe("completeLiquidation", async function () {
    it("should fail for invalid liquidationId", async () => {
      let invalidLiquidationId = 10;

      await expect(
        qredos
          .connect(liquidator)
          .completeLiquidation(invalidLiquidationId, buyer.address)
      ).to.be.revertedWith("No such record");
    });
    it("should emit CompleteLiquidation event if successfull", async () => {
      let liquidation = await qredosStore.getLiquidationByID(LIQUIDATION_ID);
      let poolBalanceBefore = await WETH.balanceOf(poolRegistry.address);
      await WETH.connect(liquidator).approve(
        qredos.address,
        liquidation.discountAmount
      );
      let txn = await qredos
        .connect(liquidator)
        .completeLiquidation(LIQUIDATION_ID, buyer.address);
      let reciept = await txn.wait();
      // console.log(reciept.events)
      expect(reciept).to.emit(qredos, "CompleteLiquidation");

      // should increase oracle balance if successfull
      let poolBalanceAfter = await WETH.balanceOf(poolRegistry.address);
      expect(poolBalanceBefore).to.be.lessThan(poolBalanceAfter);
    });
    it("should update liquidation state if successfull", async () => {
      let liquidation = await qredosStore.getLiquidationByID(LIQUIDATION_ID);
      expect(liquidation.status).to.be.equal(1);
    });
    it("liquidator should own NFT if successfull", async () => {
      let result = await BAYC.ownerOf(2);
      expect(result).to.be.equal(liquidator.address);
    });
  });

  describe("closePool", async function () {
    it("should fail for invalid poolId", async () => {
      let invalidPoolId = 10;
      await expect(
        qredos.connect(liquidator).closePool(invalidPoolId, lender.address)
      ).to.be.revertedWith("getPoolByID: No such record");
    });
    it("should emit PoolClosed event & fund poolOwner if successfull", async () => {
      let poolOwnerBalanceBefore = await WETH.balanceOf(lender.address);

      let txn = await qredos.connect(lender).closePool(POOL_ID, lender.address);
      let reciept = await txn.wait();

      expect(reciept).to.emit(qredos, "PoolClosed");
      // should fund poolOwner if successfull
      let poolOwnerBalanceAfter = await WETH.balanceOf(lender.address);
      expect(poolOwnerBalanceAfter).to.be.greaterThan(poolOwnerBalanceBefore);
    });
    it("should set poolStatus to closed if successfull", async () => {
      let pool = await poolRegistryStore.getPoolByID(POOL_ID);
      expect(pool.status).to.be.equal(1);
    });
  });

  describe("whenNotPaused", async function () {
    it("should revert when paused", async () => {
      let downPaymentAmount = parseEther("100000");
      let invalidPrincipal = parseEther("100000");

      await qredos.toggleIsPaused();

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
      ).to.be.revertedWith("Qredos: currently paused!");
    });
  });
});
