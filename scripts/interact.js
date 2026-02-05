const hre = require("hardhat");

const TRUTHBOND = "0x0D151Ee0Ac7c667766406eBef464554f408E8CEc";
const USDC = "0x036CbD53842c5426634e7929541eC2318f3dCF7e";

async function main() {
  const [signer] = await hre.ethers.getSigners();
  console.log("Using wallet:", signer.address);
  
  // Get contracts
  const truthBond = await hre.ethers.getContractAt("TruthBond", TRUTHBOND);
  const usdc = await hre.ethers.getContractAt("IERC20", USDC);
  
  // Check balances
  const usdcBalance = await usdc.balanceOf(signer.address);
  console.log("USDC balance:", hre.ethers.formatUnits(usdcBalance, 6), "USDC");
  
  // Check current market count
  const marketCount = await truthBond.marketCount();
  console.log("Current markets:", marketCount.toString());
  
  // Step 1: Approve USDC spending (need 10 for bond)
  console.log("\n--- Step 1: Approve USDC ---");
  const approveAmount = hre.ethers.parseUnits("20", 6); // 20 USDC
  const approveTx = await usdc.approve(TRUTHBOND, approveAmount);
  await approveTx.wait();
  console.log("Approved 20 USDC for TruthBond");
  
  // Step 2: Create a market
  console.log("\n--- Step 2: Create Market ---");
  const question = "Will the USDC Hackathon have more than 10 submissions?";
  const duration = 3 * 24 * 60 * 60; // 3 days
  
  const createTx = await truthBond.createMarket(question, duration);
  const receipt = await createTx.wait();
  console.log("Market created! Tx:", receipt.hash);
  
  // Get market ID from event
  const count = await truthBond.marketCount();
  const marketId = count - 1n;
  console.log("Market ID:", marketId.toString());
  
  // Step 3: Stake on YES
  console.log("\n--- Step 3: Stake 2 USDC on YES ---");
  const stakeAmount = hre.ethers.parseUnits("2", 6); // 2 USDC
  const stakeTx = await truthBond.stake(marketId, true, stakeAmount);
  await stakeTx.wait();
  console.log("Staked 2 USDC on YES!");
  
  // Step 4: Check market state
  console.log("\n--- Market State ---");
  const market = await truthBond.getMarket(marketId);
  console.log("Question:", market.question);
  console.log("Creator:", market.creator);
  console.log("Deadline:", new Date(Number(market.resolutionDeadline) * 1000).toISOString());
  console.log("Total YES:", hre.ethers.formatUnits(market.totalYes, 6), "USDC");
  console.log("Total NO:", hre.ethers.formatUnits(market.totalNo, 6), "USDC");
  console.log("Resolved:", market.resolved);
  
  // Check user stake
  const userStake = await truthBond.getUserStake(marketId, signer.address);
  console.log("\nYour stake - YES:", hre.ethers.formatUnits(userStake.yesStake, 6), "USDC");
  console.log("Your stake - NO:", hre.ethers.formatUnits(userStake.noStake, 6), "USDC");
  
  console.log("\n✅ TruthBond is working!");
  console.log("View on BaseScan:", `https://sepolia.basescan.org/address/${TRUTHBOND}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
