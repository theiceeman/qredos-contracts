const { parseEther } = require("ethers/lib/utils");

async function createPool(qredos, lender, amount) {
  let _amount = parseEther(String(amount)); // 50000
  console.log("lender", lender.address);
  let txn = await qredos
    .connect(lender)
    .createPool(_amount, 3, 30, 7890000, 3, lender.address);
  let result = await txn.wait();
  let PoolCreatedEvent = result.events?.filter((x) => {
    return x.event == "PoolCreated";
  });
  return PoolCreatedEvent[0].args.poolId;
}

async function purchaseNFT(
  qredos,
  tokenAddress,
  tokenId,
  downPaymentAmount,
  principalAmount,
  POOL_ID
) {
  let txn = await qredos
    .connect(buyer)
    .purchaseNFT(
      tokenAddress,
      tokenId,
      downPaymentAmount,
      principalAmount,
      POOL_ID
    );
  let result = await txn.wait();

  let PurchaseCreatedEvent = result.events?.filter((x) => {
    return x.event == "PurchaseCreated";
  });
  return PurchaseCreatedEvent[0].args.purchaseId;
}

module.exports = {
  createPool,
  purchaseNFT,
};
