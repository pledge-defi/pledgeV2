



async function main() {

  const [deployer] = await ethers.getSigners();

  console.log(
    "Deploying contracts with the account:",
    deployer.address
  );

  console.log("Account balance:", (await deployer.getBalance()).toString());

  const Token = await ethers.getContractFactory("PledgePool");
  const token = await Token.deploy("0x4C59D8C05Ab4138e92cd3FAE8a0454364719A6ce","0x7bAb582C8D90B1F9E2d8998547e43507249046A7",
                    "0xB20Ad357fD682E91BDdCcf408DaBA9E837920914","0x07A8929EeC07fFBd4d284900A87063F89bdc288A");

  console.log("Token address:", token.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });