// We require the Hardhat Runtime Environment explicitly here. This is optional 
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile 
  // manually to make sure everything is compiled
  // await hre.run('compile');
  let contractAddress = "0xcdC5A05A0A68401d5FCF7d136960CBa5aEa990Dd";
  await hre.run("verify:verify", {
    address: contractAddress,
    constructorArguments: [
        [
        "0x481a65e50522602f6f920E6b797Df85b6182f948",
        "0x03fb15c1Bbe875f3869D7b5EAAEB31111deA876F",
        "0x3B720fBacd602bccd65F82c20F8ECD5Bbb295c0a"
        ],
        2
    ]
  })
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
