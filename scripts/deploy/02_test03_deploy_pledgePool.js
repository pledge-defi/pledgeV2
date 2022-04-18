// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

// pro
// let oracleAddress = "0x4Aa9EB3149089D7208C9C0403BF1b9bA25ff05BD";
// let swapRouter = "0x1088d1860f4E51A2e20440eD23619a1D0D59beB0";
// let feeAddress = "0x59f71A607E5D409e75625235a3C583f336017f8E";
// let multiSignatureAddress = "0xeF75E3A7315BD1c023677f4DdAA951A0Bb503C6D";

// dev
let oracleAddress = "0x4F72DFa7E151767eC583bbaE7cf878Ed12d6c111";
let swapRouter = "0xbe9c40a0eab26a4223309ea650dea0dd4612767e";
let feeAddress = "0x59f71A607E5D409e75625235a3C583f336017f8E";


async function main() {

  const [deployer,,,,] = await ethers.getSigners();

  console.log(
    "Deploying contracts with the account:",
    deployer.address
  );

  console.log("Account balance:", (await deployer.getBalance()).toString());

  const pledgePoolToken = await ethers.getContractFactory("PledgePool");
  const pledgeAddress = await pledgePoolToken.deploy(oracleAddress,swapRouter,feeAddress);


  console.log("pledgeAddress address:", pledgeAddress.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });