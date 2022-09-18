const { BigNumber } = require("ethers");
const crypto = require("crypto");
const { ethers } = require("hardhat");

async function transferEther(signer, _to, _ethAmount) {
  let tx = {
    to: _to,
    value: ethers.utils.parseEther(_ethAmount), //  convert Eth to Wei
  };
  let result = await signer.sendTransaction(tx);
  return result;
}

function genAddresses() {
  // Generate private key
  // console.log("Printing for wallet address ", i);
  var id = crypto.randomBytes(32).toString("hex");
  var privateKey = "0x" + id;
  // console.log("SAVE BUT DO NOT SHARE THIS:", privateKey);

  // Generate wallet(public key) from prv key
  var wallet = new ethers.Wallet(privateKey);
  // console.log("Address: " + wallet.address);
  return wallet;
}

async function impersonateAccount(acctAddress) {
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [acctAddress],
  });
  return await ethers.getSigner(acctAddress);
}

// Returns the time of the last mined block in seconds
async function latestTime() {
  let block = await hre.ethers.provider.getBlock("latest");
  return block.timestamp;
}

/* 
    // opening time will be in one week
    this.openingTime = latestTime() + duration.weeks(1);

    // will close one week after opening time
    this.closingTime = this.openingTime + duration.weeks(1);

    // For the test, advance blockchain time to time when the presale start
    await increaseTimeTo(this.openingTime + 1);

 */

/**
 * Forwards blockchain time to the passed argument in seconds.
 *
 * @param target time in seconds
 */
async function increaseTimeTo(target) {
  try {
    let now = await latestTime();
    if (target < now)
      throw Error(
        `Cannot increase current time(${now}) to a moment in the past(${target})`
      );

    let res = await ethers.provider.send("evm_mine", [target]);
    return res;
  } catch (err) {
    console.log(err);
  }
}

const duration = {
  seconds: function (val) {
    return val;
  },
  minutes: function (val) {
    return val * this.seconds(60);
  },
  hours: function (val) {
    return val * this.minutes(60);
  },
  days: function (val) {
    return val * this.hours(24);
  },
  weeks: function (val) {
    return val * this.days(7);
  },
  years: function (val) {
    return val * this.days(365);
  },
};

module.exports = {
  transferEther,
  impersonateAccount,
  genAddresses,
  latestTime,
  increaseTimeTo,
  duration,
};
