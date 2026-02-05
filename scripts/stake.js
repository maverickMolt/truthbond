const hre = require("hardhat");

const TRUTHBOND = "0x0D151Ee0Ac7c667766406eBef464554f408E8CEc";
const USDC = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";

async function main() {
  const [signer] = await hre.ethers.getSigners();
  console.log("Using wallet:", signer.address);
  
  const truthBond = await hre.ethers.getContractAt("TruthBond", TRUTHBOND);
  const usdc = await hre.ethers.getContractAt("IERC20", USDC);
  
  // Check current state
  const marketCount = await truthBond.marketCount();
  console.log("Markets created:", marketCount.toString());
  
  if (marketCount === 0n) {
    console.log("No markets yet!");
    return;
  }
  
  const marketId = 0n; // First market
  
  // Check market state
  console.log("\n--- Market 0 State ---");
  const market = await truthBond.getMarket(marketId);
  console.log("Question:", market.question);
  console.log("Total YES:", hre.ethers.formatUnits(market.totalYes, 6), "USDC");
  console.log("Total NO:", hre.ethers.formatUnits(market.totalNo, 6), "USDC");
  console.log("Resolved:", market.resolved);
  console.log("Deadline:", new Date(Number(market.resolutionDeadline) * 1000).toISOString());
  
  // Stake on YES
  console.log("\n--- Staking 2 USDC on YES ---");
  const stakeAmount = hre.ethers.parseUnits("2", 6);
  const stakeTx = await truthBond.stake(marketId, true, stakeAmount);
  await stakeTx.wait();
  console.log("Staked! Tx:", stakeTx.hash);
  
  // Check updated state
  const marketAfter = await truthBond.getMarket(marketId);
  console.log("\nUpdated Total YES:", hre.ethers.formatUnits(marketAfter.totalYes, 6), "USDC");
  
  // Check user stake
  const userStake = await truthBond.getUserStake(marketId, signer.address);
  console.log("Your YES stake:", hre.ethers.formatUnits(userStake.yesStake, 6), "USDC");
  console.log("Your NO stake:", hre.ethers.formatUnits(userStake.noStake, 6), "USDC");
  
  console.log("\n✅ Done!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
