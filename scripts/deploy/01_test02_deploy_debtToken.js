// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

let tokenName = "spBUSD_1";
let tokenSymbol = "spBUSD_1";
let multiSignatureAddress = "0xeF75E3A7315BD1c023677f4DdAA951A0Bb503C6D";

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