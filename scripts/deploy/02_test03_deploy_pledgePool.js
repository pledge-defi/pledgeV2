// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

let oracleAddress = "0x272aCa56637FDaBb2064f19d64BC3dE64A85A1b2";
let swapRouter = "0xbe9c40a0eab26a4223309ea650dea0dd4612767e";
let feeAddress = "0x0ff66Eb23C511ABd86fC676CE025Ca12caB2d5d4";
let multiSignatureAddress = "0xcdC5A05A0A68401d5FCF7d136960CBa5aEa990Dd";

async function main() {

  const [deployerMax,,,,deployerMin] = await ethers.getSigners();

  console.log(
    "Deploying contracts with the account:",
    deployerMin.address
  );

  console.log("Account balance:", (await deployerMin.getBalance()).toString());

  const pledgePoolToken = await ethers.getContractFactory("PledgePool");
  const pledgeAddress = await pledgePoolToken.connect(deployerMin).deploy(oracleAddress,swapRouter,feeAddress, multiSignatureAddress);


  console.log("pledgeAddress address:", pledgeAddress.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });