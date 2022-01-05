// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.


let multiSignatureAddress = "0xeF75E3A7315BD1c023677f4DdAA951A0Bb503C6D";

async function main() {

  const [deployerMax,,,,deployerMin] = await ethers.getSigners();

  console.log(
    "Deploying contracts with the account:",
    deployerMin.address
  );

  console.log("Account balance:", (await deployerMin.getBalance()).toString());

  const oracleToken = await ethers.getContractFactory("BscPledgeOracle");
  const oracle = await oracleToken.connect(deployerMin).deploy(multiSignatureAddress);

  console.log("Oracle address:", oracle.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });