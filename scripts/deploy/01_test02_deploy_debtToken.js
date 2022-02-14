// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

let tokenName = "spBTC_1";
let tokenSymbol = "spBTC_1";
let multiSignatureAddress = "0xcdC5A05A0A68401d5FCF7d136960CBa5aEa990Dd";

async function main() {

  const [deployerMax,,,,deployerMin] = await ethers.getSigners();

  console.log(
    "Deploying contracts with the account:",
    deployerMin.address
  );

  console.log("Account balance:", (await deployerMin.getBalance()).toString());

  const debtToken = await ethers.getContractFactory("DebtToken");
  const DebtToken = await debtToken.connect(deployerMin).deploy(tokenName,tokenSymbol,multiSignatureAddress);

  console.log("DebtToken address:", DebtToken.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });