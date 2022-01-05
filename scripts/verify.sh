

# (0) multiSignature address
# deploy
npx hardhat run 03_test03_deploy_multiSignature.js --network bsctest
# verify multiSignature
npx hardhat run   verify.js --network bsctest


# (1) oracle address
# deploy
npx hardhat run 00_test01_deploy_oracle.js  --network bsctest
# verify
npx hardhat verify 0x272aCa56637FDaBb2064f19d64BC3dE64A85A1b2 "0xcdC5A05A0A68401d5FCF7d136960CBa5aEa990Dd" --network bsctest


# (2) debt token address
# deploy
npx hardhat run 01_test02_deploy_debtToken.js  --network bsctest
#verify
npx hardhat verify 0xC9512aAE24c775ad57D121F8d57e5674AA44EE12 "spBUSD_1" "spBUSD_1" "0xcdC5A05A0A68401d5FCF7d136960CBa5aEa990Dd" --network bsctest

# (3) pledge pool address
# deploy
npx hardhat run 02_test03_deploy_pledgePool.js --network bsctest
# verify
npx hardhat verify 0x25d9226292c8B5dfdadAcD97B1A54981D680D311 "0x272aCa56637FDaBb2064f19d64BC3dE64A85A1b2" "0xbe9c40a0eab26a4223309ea650dea0dd4612767e" "0x0ff66Eb23C511ABd86fC676CE025Ca12caB2d5d4" "0xcdC5A05A0A68401d5FCF7d136960CBa5aEa990Dd" --network bsctest

