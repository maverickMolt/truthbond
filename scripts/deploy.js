const hre = require("hardhat");

async function main() {
  // Base Sepolia USDC address
  const USDC_ADDRESS = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";
  
  console.log("Deploying TruthBond to Base Sepolia...");
  console.log("USDC address:", USDC_ADDRESS);
  
  const TruthBond = await hre.ethers.getContractFactory("TruthBond");
  const truthBond = await TruthBond.deploy(USDC_ADDRESS);
  
  await truthBond.waitForDeployment();
  
  const address = await truthBond.getAddress();
  console.log("TruthBond deployed to:", address);
  console.log("");
  console.log("Verify with:");
  console.log(`npx hardhat verify --network baseSepolia ${address} ${USDC_ADDRESS}`);
  
  return address;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
