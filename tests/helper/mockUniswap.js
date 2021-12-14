const { ethers } = require("hardhat");
const BN = web3.utils.BN;

async function mockUniswap (minter, weth) {
    const UniswapV2Factory = await ethers.getContractFactory("UniswapV2Factory");
    let uniswapFactory = await UniswapV2Factory.deploy(minter.address);

    const UniswapV2Router02 = await ethers.getContractFactory("UniswapV2Router02");
    let uniswapRouter = await UniswapV2Router02.deploy(uniswapFactory.address, weth.address);
    return [uniswapRouter, uniswapFactory]
    
}
// targetToken: {address: string, price: int}
async function mockPairs(router, factory, weth, alice, targetTokens) {
    let decimals = 1e6
    const APPROVE_AMOUNT = 100000
    let timestamp = new BN(new Date().getTime())
    // add pair between tokens and eth
    targetTokens.forEach(async (targetToken) => {
        await targetToken.artifact.connect(alice).approve(router.address, APPROVE_AMOUNT * decimals);
        
        // let pair = await factory.getPair(targetToken.address, weth.address);
        await router.connect(alice).addLiquidityETH(
            targetToken.address,
            decimals,
            targetToken.price * decimals,// eth amount will be the price * decimals
            targetToken.price * decimals,
            alice.address,
            timestamp.add(new BN(100000)).toString(), {value: decimals}
        )
    });
    // add pair between tokens
    targetTokens.forEach(async (targetToken1) => {
        targetTokens.forEach(async (targetToken2) => {
            if (targetToken1.address != targetToken2.address) {
                await router.connect(alice).addLiquidity(
                   targetToken1.address,
                    targetToken2.address,
                    targetToken2.price * decimals, // the deposit of token1 is the price of token2 * decimals
                    targetToken1.price * decimals,
                    targetToken2.price * decimals,
                    targetToken1.price * decimals,
                    alice.address,
                    timestamp.add(new BN(100000)).toString()
                )
            }
        })
    })
    
}

module.exports = {
    mockUniswap,
    mockPairs
};