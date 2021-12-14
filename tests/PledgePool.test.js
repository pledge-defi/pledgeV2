const { expect } = require("chai");
const { show } = require("./helper/meta.js");
const { initAll } = require("./helper/init.js");
var sleep  = require('sleep');


describe("PledgePool", function (){
    let busdAddress, btcAddress, spAddress,jpAddress, bscPledgeOracle, pledgeAddress;
    let weth,factory,router;
    beforeEach(async ()=>{
        [minter, alice, bob, carol, _] = await ethers.getSigners();
        // oracle
        const bscPledgeOracleToken = await ethers.getContractFactory("BscPledgeOracle");
        bscPledgeOracle = await bscPledgeOracleToken.deploy();
        //spAddress,jpAddress
        const spToken = await ethers.getContractFactory("DebtToken");
        spAddress = await spToken.deploy("spBUSD_1","spBUSD_1");
        const jpToken = await ethers.getContractFactory("DebtToken");
        jpAddress = await jpToken.deploy("jpBTC_1", "jpBTC_1");
        // swap router Address
        [weth, factory, router, busdAddress, btcAddress] = await initAll(minter);
        // pledgeAdddress
        const pledgeToken = await ethers.getContractFactory("PledgePool");
        pledgeAddress = await pledgeToken.deploy(bscPledgeOracle.address, router.address, minter.address);
    });

    function initCreatePoolInfo(pledgeAddress, minter, time0, time1){
        // init pool info
        let timestamp = Date.parse(new Date());
        let settleTime = (timestamp/1000 + time0);
        let endTime = (settleTime + time1);
        let interestRate = 1000000;
        let maxSupply = BigInt(100000000000000000000000);
        let martgageRate = 200000000;
        let autoLiquidateThreshold = 20000000;
        pledgeAddress.connect(minter).createPoolInfo(settleTime,endTime,interestRate,maxSupply,martgageRate,
            busdAddress.address,btcAddress.address,spAddress.address,jpAddress.address, autoLiquidateThreshold);

    }



    it("check if mint right", async function() {
        // sp token and jp token mint
        await spAddress.addMinter(minter.address);
        await spAddress.connect(minter).mint(alice.address, BigInt(100000000));
        expect(await spAddress.totalSupply()).to.equal('100000000');
        expect(await spAddress.balanceOf(alice.address)).to.equal('100000000');
    });

    it("Create Pool info",async function (){
        // create pool info
       await initCreatePoolInfo(pledgeAddress,minter, 100,200);
        // get pool info length
        expect(await pledgeAddress.poolLength()).to.be.equal(1);
    });

    it ("deposit lend after create pool info", async function (){
        // create pool info
        await initCreatePoolInfo(pledgeAddress,minter, 100,200);
        // approve
        await busdAddress.connect(minter).approve(pledgeAddress.address, BigInt(1000*1e18));
        // deposit lend
        await pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18));
        // check info
        let num = await pledgeAddress.userLendInfo(minter.address,0);
        expect(num[0]).to.be.equal(BigInt(1000000000000000000000).toString());
    });

    it ("pause check", async function (){
        // create pool info
        await initCreatePoolInfo(pledgeAddress,minter, 100, 200);
        // approve
        await busdAddress.connect(minter).approve(pledgeAddress.address, BigInt(1000*1e18));
        // deposit lend
        await pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18));
        // check info
        let num = await pledgeAddress.userLendInfo(minter.address,0);
        expect(num[0]).to.be.equal(BigInt(1000000000000000000000).toString());
        // paused
        await pledgeAddress.connect(minter).setPause();
        expect(pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18))).to.be.revertedWith("Stake has been suspended");
    });

    it("pool state check", async function (){
        // create pool info
        await initCreatePoolInfo(pledgeAddress,minter, 100, 200);
        // approve
        await busdAddress.connect(minter).approve(pledgeAddress.address, BigInt(1000*1e18));
        // deposit lend
        await pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18));
        // update pool state
        expect(pledgeAddress.connect(minter).settle(0)).to.be.revertedWith("settle: less than settleTime");
    });

})




