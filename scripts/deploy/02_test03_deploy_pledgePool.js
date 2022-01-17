// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

let oracleAddress = "0x72D8E6144A46b7b51F59831A9D38C7f9E682B7C1";
let swapRouter = "0xbe9c40a0eab26a4223309ea650dea0dd4612767e";
let feeAddress = "0x0ff66Eb23C511ABd86fC676CE025Ca12caB2d5d4";
// let multiSignatureAddress = "0xeF75E3A7315BD1c023677f4DdAA951A0Bb503C6D";

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