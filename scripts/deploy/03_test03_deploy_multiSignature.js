



let multiSignatureAddress = ["0x481a65e50522602f6f920E6b797Df85b6182f948",
                            "0x03fb15c1Bbe875f3869D7b5EAAEB31111deA876F",
                            "0x3B720fBacd602bccd65F82c20F8ECD5Bbb295c0a"];
let threshold = 2;


async function main() {

  const [deployerMax,,,,deployerMin] = await ethers.getSigners();

  console.log(
    "Deploying contracts with the account:",
    deployerMax.address
  );

  console.log("Account balance:", (await deployerMax.getBalance()).toString());

  const multiSignatureToken = await ethers.getContractFactory("multiSignature");
  const multiSignature = await multiSignatureToken.connect(deployerMax).deploy(multiSignatureAddress, threshold);

  console.log("multiSignature address:", multiSignature.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });