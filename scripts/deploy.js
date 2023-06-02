
const { parseEther } = require("ethers/lib/utils");
const hre = require("hardhat");

/* 
  erc20token:0x2dccF6aE5d7CFab214f0E97B7695B5267e3efA91
  PoolRegistryStore:0x2902Bf62c6efc2679eF69894aaC02976f65C2920
  QredosStore:0xDb2F3d711049E106F2B820F1b9db772ecA7Bf5e8
  PoolRegistry: 0x5f200A6965594f8cEA96ccE4E5F5E10C81cA58C7
  Qredos: 0x821c80E9507A7D87b6103B9a292e10729A6817b9

 */

/* 
WETH 0x8c0182CB2354dE51Ce2CFe1C5b6b00fa6D298b8F
BAYC 0x6C630c4B42AdAAA67A1029655f104d9Ce1F54011
poolRegistryStore 0x9e63Af0170AD996115DFbE7D69754D3aAf991d76
qredosStore 0x6605ABe7345524496551681fe1874D745DA3D4e3
 */

async function main() {
  [deployer, buyer, lender, liquidator] = await hre.ethers.getSigners();

  const weth = await ethers.getContractFactory("ERC20Token");
  const WETH = await weth.deploy("Wrapped Ether", "WETH");
  console.log('WETH', WETH.address)

  const bayc = await ethers.getContractFactory("ERC721Token");
  const BAYC = await bayc.deploy();
  BAYC.safeMint(deployer.address, 0);

  console.log('BAYC', BAYC.address)

  const PoolRegistryStore = await ethers.getContractFactory("PoolRegistryStore");
  const poolRegistryStore = await PoolRegistryStore.deploy();

  console.log('poolRegistryStore', poolRegistryStore.address)
  // 
  const QredosStore = await ethers.getContractFactory("QredosStore");
  const qredosStore = await QredosStore.deploy();

  console.log('qredosStore', qredosStore.address)
  // Pool
  const PoolRegistry = await ethers.getContractFactory("PoolRegistry");
  const poolRegistry = await PoolRegistry.deploy(
    WETH.address,
    poolRegistryStore.address
  );

  console.log('poolRegistry', poolRegistry.address)
  // Oracle
  const Qredos = await ethers.getContractFactory("Qredos");
  const qredos = await Qredos.deploy(
    WETH.address,
    poolRegistry.address,
    qredosStore.address
  );

  console.log('qredos', qredos.address)

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
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
