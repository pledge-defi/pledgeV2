const BN = web3.utils.BN;
const zeroAddress = "0x0000000000000000000000000000000000000000"

async function initFactory(minter) {
    // factory
    const Factory = await ethers.getContractFactory("UniswapV2Factory");
    // set feeTo setter to minter
    factory = await Factory.deploy(minter.address)
    return factory;
}


async function initWETH() {
    // @Notice Mock WETH, will be replaced in formal deploy
    const WETH = await ethers.getContractFactory("WETH9");
    weth = await WETH.deploy()
    return weth;
}


async function initRouter(factory, weth) {
    const Rounter = await ethers.getContractFactory("UniswapV2Router02");
    router = await Rounter.deploy(factory.address, weth.address)
    return router
}


async function initBusd(){
    const Busd = await  ethers.getContractFactory("BEP20Token");
    busd = await Busd.deploy();
    return busd
}

async function initBtc() {
    const Btc= await ethers.getContractFactory("BtcToken");
    btc = await Btc.deploy();
    return btc
}

async function initAll(minter) {
    // mock weth
    let weth = await initWETH();
    let factory = await initFactory(minter);
    // build router binded with factory and weth
    let router = await initRouter(factory, weth);

    let busd = await initBusd();
    let btc = await initBtc()

    return [weth, factory, router, busd, btc]
}

module.exports = {
    initWETH,
    initFactory,
    initRouter,
    initAll
};