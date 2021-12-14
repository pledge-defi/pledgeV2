// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

let tokenName = "spBUSD_1";
let tokenSymbol = "spBUSD_1";

async function main() {

  const [deployer] = await ethers.getSigners();

  console.log(
    "Deploying contracts with the account:",
    deployer.address
  );

  console.log("Account balance:", (await deployer.getBalance()).toString());

  const debtToken = await ethers.getContractFactory("DebtToken");
  const DebtToken = await debtToken.deploy(tokenName,tokenSymbol);

  console.log("DebtToken address:", DebtToken.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });