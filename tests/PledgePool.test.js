const { expect } = require("chai");
const { show } = require("./helper/meta.js");
const { initAll } = require("./helper/init.js");
const {latestBlock, advanceBlockTo, latestBlockNum, stopAutoMine, latest, increase} = require("./helper/time.js");
const {mockUniswap, mockAddLiquidity,mockSwap} = require('./helper/mockUniswap.js')
const BN = web3.utils.BN;

describe("PledgePool", function (){
    let busdAddress, btcAddress, spAddress,jpAddress, bscPledgeOracle, pledgeAddress;
    let weth,factory,router;
    beforeEach(async ()=>{
        await stopAutoMine();
        [minter, alice, bob, carol, _] = await ethers.getSigners();
        // oracle
        const bscPledgeOracleToken = await ethers.getContractFactory("MockOracle");
        bscPledgeOracle = await bscPledgeOracleToken.deploy();
        //spAddress,jpAddress
        const spToken = await ethers.getContractFactory("DebtToken");
        spAddress = await spToken.deploy("spBUSD_1","spBUSD_1");
        const jpToken = await ethers.getContractFactory("DebtToken");
        jpAddress = await jpToken.deploy("jpBTC_1", "jpBTC_1");
        // swap router Address
        [weth, factory, router, busdAddress, btcAddress] = await initAll(minter);
        // pledgeAdddress
        const pledgeToken = await ethers.getContractFactory("MockPledgePool");
        pledgeAddress = await pledgeToken.deploy(bscPledgeOracle.address, router.address, minter.address);
    });

    async function initCreatePoolInfo(pledgeAddress, minter, time0, time1){
        // init pool info
        let startTime = await latest();
        let settleTime = (parseInt(startTime) + parseInt(time0));
        show({settleTime});
        let endTime = (parseInt(settleTime) + parseInt(time1));
        show({endTime});
        let interestRate = 1000000;
        let maxSupply = BigInt(100000000000000000000000);
        let martgageRate = 200000000;
        let autoLiquidateThreshold = 20000000;
        await pledgeAddress.connect(minter).createPoolInfo(settleTime,endTime,interestRate,maxSupply,martgageRate,
            busdAddress.address,btcAddress.address,spAddress.address,jpAddress.address, autoLiquidateThreshold);
    }

    it("check if mint right", async function() {
        // sp token and jp token mint
        await spAddress.addMinter(minter.address);
        await jpAddress.addMinter(minter.address);
        await spAddress.connect(minter).mint(alice.address, BigInt(100000000));
        await jpAddress.connect(minter).mint(alice.address, BigInt(100000000));
        expect(await spAddress.totalSupply()).to.equal(BigInt(100000000).toString());
        expect(await spAddress.balanceOf(alice.address)).to.equal(BigInt(100000000).toString());
        expect(await jpAddress.totalSupply()).to.equal(BigInt(100000000).toString());
        expect(await jpAddress.balanceOf(alice.address)).to.equal(BigInt(100000000).toString());

    });

    it("Create Pool info",async function (){
        // create pool info
       await initCreatePoolInfo(pledgeAddress, minter, 100,200);
        // get pool info length
        expect(await pledgeAddress.poolLength()).to.be.equal(1);
    });

    it("Non-administrator creates pool", async function (){
        await expect(initCreatePoolInfo(pledgeAddress, alice, 100, 200)).to.revertedWith("Ownable: caller is not the owner");
    });

    it ("deposit lend after create pool info, pool state is match", async function (){
        // create pool info
        await initCreatePoolInfo(pledgeAddress, minter, 100,200);
        // Determine the status of the pool
        expect(await pledgeAddress.getPoolState(0)).to.equal(0);
        // approve
        await busdAddress.connect(minter).approve(pledgeAddress.address, BigInt(1000*1e18));
        show(await pledgeAddress.poolLength());
        // deposit lend
        await pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18));
        // check info
        let data = await pledgeAddress.userLendInfo(minter.address,0);
        show({data});
        expect(data[0]).to.be.equal(BigInt(1000*1e18).toString());
        // increase
        await increase(1000);
        await expect(pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18))).to.revertedWith("Less than this time")
    });

    it ("deposit borrow after create pool info, pool state is match", async function (){
        await initCreatePoolInfo(pledgeAddress, minter, 1000,2000);
        expect(await pledgeAddress.getPoolState(0)).to.equal(0);
        await btcAddress.connect(minter).approve(pledgeAddress.address, BigInt(1000*1e18));
        let timestamp = await latest();
        let deadLine = timestamp + 100 ;
        await pledgeAddress.connect(minter).depositBorrow(0, BigInt(1000*1e18),deadLine);
        let data = await pledgeAddress.userBorrowInfo(minter.address,0);
        show({data});
        expect(data[0]).to.be.equal(BigInt(1000*1e18).toString());
        await increase(1000);
        await expect(pledgeAddress.connect(minter).depositBorrow(0, BigInt(1000*1e18), deadLine)).to.revertedWith("Less than this time")

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
        expect(pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18))).to.revertedWith("Stake has been suspended");
    });

    it("pool state check", async function (){
        let blockNum = await latestBlock();
        show({blockNum});
        let newTime = await latest();
        show({newTime});
        await initCreatePoolInfo(pledgeAddress,minter, 100, 200);
        let poolstate = await pledgeAddress.getPoolState(0);
        show({poolstate});
        await busdAddress.connect(minter).approve(pledgeAddress.address, BigInt(1000*1e18));
        await pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18));
        await advanceBlockTo(100);
        let blockNum1 = await latestBlock();
        show({blockNum1});
        let endtime = await latest();
        show({endtime});
        // increse
        await increase(1000);
        // update pool state
        await pledgeAddress.connect(minter).settle(0);
        expect(await pledgeAddress.getPoolState(0)).to.equal(4);
    });

    it("emergencyLendWithdrawal for lend, pool state is undone", async function (){
        await initCreatePoolInfo(pledgeAddress, minter, 100,200);
        expect(await pledgeAddress.getPoolState(0)).to.equal(0);
        await busdAddress.connect(minter).approve(pledgeAddress.address, BigInt(1000*1e18));
        await pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18));
        // increse
        await increase(1000);
        await pledgeAddress.connect(minter).settle(0);
        expect(await pledgeAddress.getPoolState(0)).to.equal(4);
        // lend emergency in undone
        await pledgeAddress.connect(minter).emergencyLendWithdrawal(0);
        let data = await pledgeAddress.userLendInfo(minter.address,0);
        expect(data[2]).to.equal(true);
    });

    it("emergencyBorrowWithdrawal for borrow, pool state is undone", async function (){
        await initCreatePoolInfo(pledgeAddress, minter, 100,200);
        expect(await pledgeAddress.getPoolState(0)).to.equal(0);
        await btcAddress.connect(minter).approve(pledgeAddress.address, BigInt(1000*1e18));
        let timestamp = await latest();
        let deadLine = timestamp + 100 ;
        await pledgeAddress.connect(minter).depositBorrow(0, BigInt(1000*1e18),deadLine);
        // increase
        await increase(1000);
        await pledgeAddress.connect(minter).settle(0);
        expect(await pledgeAddress.getPoolState(0)).to.equal(4);
        // lend emergency in undone
        await pledgeAddress.connect(minter).emergencyBorrowWithdrawal(0);
        let data = await pledgeAddress.userBorrowInfo(minter.address,0);
        expect(data[2]).to.equal(true);
    });

    it("claim spToken or jpToken, pool state is execution", async function (){
        await initCreatePoolInfo(pledgeAddress, minter, 100,200);
        expect(await pledgeAddress.getPoolState(0)).to.equal(0);
        // borrow
        await btcAddress.connect(minter).approve(pledgeAddress.address, BigInt(500*1e18));
        let timestamp = await latest();
        let deadLine = timestamp + 100 ;
        await pledgeAddress.connect(minter).depositBorrow(0, BigInt(500*1e18),deadLine);
        // lend
        await busdAddress.connect(minter).approve(pledgeAddress.address, BigInt(1000*1e18));
        await pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18));
        // increase
        await increase(1000);
        // add  oracle price
        await bscPledgeOracle.connect(minter).setPrice(busdAddress.address,BigInt(1e8));
        await bscPledgeOracle.connect(minter).setPrice(btcAddress.address,BigInt(1e8));
        // settle
        await increase(1000);
        await pledgeAddress.connect(minter).settle(0);
        show(await pledgeAddress.getPoolState(0));
        expect(await pledgeAddress.getPoolState(0)).to.equal(BigInt(1).toString(16));
        // claim sp_token or jp_token
        let poolDataInfo = await pledgeAddress.poolDataInfo(0);
        show({poolDataInfo});
        // sp and jp add minter
        await spAddress.connect(minter).addMinter(pledgeAddress.address);
        await jpAddress.connect(minter).addMinter(pledgeAddress.address);
        // claim
        await pledgeAddress.connect(minter).claimLend(0);
        await pledgeAddress.connect(minter).claimBorrow(0);
        expect(await spAddress.balanceOf(minter.address)).to.equal(BigInt( 250000000000000000000).toString());
        expect(await jpAddress.balanceOf(minter.address)).to.equal(BigInt(500000000000000000000).toString());
    });

    it("Number of refunds, pool state is execution", async function (){
         await initCreatePoolInfo(pledgeAddress, minter, 100,200);
        expect(await pledgeAddress.getPoolState(0)).to.equal(0);
        // borrow
        await btcAddress.connect(minter).approve(pledgeAddress.address, BigInt(500*1e18));
        let timestamp = await latest();
        let deadLine = timestamp + 100 ;
        await pledgeAddress.connect(minter).depositBorrow(0, BigInt(500*1e18),deadLine);
        // lend
        await busdAddress.connect(minter).approve(pledgeAddress.address, BigInt(1000*1e18));
        await pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18));
        // increase
        await increase(1000);
        // add  oracle price
        await bscPledgeOracle.connect(minter).setPrice(busdAddress.address,BigInt(1e8));
        await bscPledgeOracle.connect(minter).setPrice(btcAddress.address,BigInt(1e8));
        // settle
        await increase(1000);
        await pledgeAddress.connect(minter).settle(0);
        show(await pledgeAddress.getPoolState(0));
        expect(await pledgeAddress.getPoolState(0)).to.equal(BigInt(1).toString(16));
        // refund
        await pledgeAddress.connect(minter).refundLend(0);
        let lendInfoData = await pledgeAddress.userLendInfo(minter.address,0);
        // expect(lendInfoData)
        show({lendInfoData});
        expect(lendInfoData[2]).to.equal(true);

    });

    it ("lend burn sp token and borrow burn jp token, pool is finish", async function (){
        await initCreatePoolInfo(pledgeAddress, minter, 100,200);
        expect(await pledgeAddress.getPoolState(0)).to.equal(0);
        // borrow
        await btcAddress.connect(minter).approve(pledgeAddress.address, BigInt(500*1e18));
        let timestamp = await latest();
        let deadLine = timestamp + 100 ;
        await pledgeAddress.connect(minter).depositBorrow(0, BigInt(500*1e18),deadLine);
        // lend
        await busdAddress.connect(minter).approve(pledgeAddress.address, BigInt(1000*1e18));
        await pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18));
        // increase
        await increase(1000);
        // add  oracle price
        await bscPledgeOracle.connect(minter).setPrice(busdAddress.address,BigInt(1e8));
        await bscPledgeOracle.connect(minter).setPrice(btcAddress.address,BigInt(1e8));
        // settle
        await increase(1000);
        await pledgeAddress.connect(minter).settle(0);
        show(await pledgeAddress.getPoolState(0));
        expect(await pledgeAddress.getPoolState(0)).to.equal(BigInt(1).toString(16));
        // claim sp_token or jp_token
        let poolDataInfo = await pledgeAddress.poolDataInfo(0);
        show({poolDataInfo});
        // sp and jp add minter
        await spAddress.connect(minter).addMinter(pledgeAddress.address);
        await jpAddress.connect(minter).addMinter(pledgeAddress.address);
        // claim
        await pledgeAddress.connect(minter).claimLend(0);
        await pledgeAddress.connect(minter).claimBorrow(0);
        expect(await spAddress.balanceOf(minter.address)).to.equal(BigInt( 250000000000000000000).toString());
        expect(await jpAddress.balanceOf(minter.address)).to.equal(BigInt(500000000000000000000).toString());
        await increase(3000);
        // add liquidate
        let deadLineAddLiquidate = timestamp + 1000;
        let busdAmount = BigInt(1000000*1e18);
        let btcAmount = BigInt(500000*1e18);
        await mockAddLiquidity(router,busdAddress,btcAddress,minter,deadLineAddLiquidate,busdAmount,btcAmount);
        // finish
        await pledgeAddress.connect(minter).finish(0);
        expect(await pledgeAddress.getPoolState(0)).to.equal(BigInt(2).toString(16));
        let poolDataInfo1 = await pledgeAddress.poolDataInfo(0);
        show({poolDataInfo1});
        // burn sp tokne,harvest lend token + interest
        let remainSp = await spAddress.balanceOf(minter.address);
        show({remainSp});
        await pledgeAddress.connect(minter).withdrawLend(0,remainSp);
        // burn jp token, harvest borrow token
        let remainJp = await jpAddress.balanceOf(minter.address);
        show({remainJp});
        await pledgeAddress.connect(minter).withdrawBorrow(0,remainJp,deadLineAddLiquidate);
    });

    it("lend burn sp token and borrow burn jp token, pool is liquidation",async function (){
        await initCreatePoolInfo(pledgeAddress, minter, 100,200);
        expect(await pledgeAddress.getPoolState(0)).to.equal(0);
        // borrow
        await btcAddress.connect(minter).approve(pledgeAddress.address, BigInt(500*1e18));
        let timestamp = await latest();
        let deadLine = timestamp + 100 ;
        await pledgeAddress.connect(minter).depositBorrow(0, BigInt(500*1e18),deadLine);
        // lend
        await busdAddress.connect(minter).approve(pledgeAddress.address, BigInt(1000*1e18));
        await pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18));
        // increase
        await increase(1000);
        // add  oracle price
        await bscPledgeOracle.connect(minter).setPrice(busdAddress.address,BigInt(1e8));
        await bscPledgeOracle.connect(minter).setPrice(btcAddress.address,BigInt(1e8));
        // settle
        await increase(1000);
        await pledgeAddress.connect(minter).settle(0);
        show(await pledgeAddress.getPoolState(0));
        expect(await pledgeAddress.getPoolState(0)).to.equal(BigInt(1).toString(16));
        // claim sp_token or jp_token
        let poolDataInfo = await pledgeAddress.poolDataInfo(0);
        show({poolDataInfo});
        // sp and jp add minter
        await spAddress.connect(minter).addMinter(pledgeAddress.address);
        await jpAddress.connect(minter).addMinter(pledgeAddress.address);
        // claim
        await pledgeAddress.connect(minter).claimLend(0);
        await pledgeAddress.connect(minter).claimBorrow(0);
        expect(await spAddress.balanceOf(minter.address)).to.equal(BigInt( 250000000000000000000).toString());
        expect(await jpAddress.balanceOf(minter.address)).to.equal(BigInt(500000000000000000000).toString());
        await increase(3000);
        // add liquidate
        let deadLineAddLiquidate = timestamp + 1000;
        let busdAmount = BigInt(1000000*1e18);
        let btcAmount = BigInt(500000*1e18);
        await mockAddLiquidity(router,busdAddress,btcAddress,minter,deadLineAddLiquidate,busdAmount,btcAmount);
        // liquidation
        // update oracle
        await bscPledgeOracle.connect(minter).setPrice(busdAddress.address,BigInt(1e8));
        await bscPledgeOracle.connect(minter).setPrice(btcAddress.address,BigInt(0.1*1e8));
        // checkout liquation state
        let result = await pledgeAddress.checkoutLiquidate(0);
        show({result});
        // liquadtion
        await pledgeAddress.connect(minter).liquidate(0);
        let poolDataInfo1 = await pledgeAddress.poolDataInfo(0);
        show({poolDataInfo1});
        // burn sp tokne,harvest lend token + interest
        let remainSp = await spAddress.balanceOf(minter.address);
        show({remainSp});
        await pledgeAddress.connect(minter).withdrawLend(0,remainSp);
        // burn jp token, harvest borrow token
        let remainJp = await jpAddress.balanceOf(minter.address);
        show({remainJp});
        await pledgeAddress.connect(minter).withdrawBorrow(0,remainJp,deadLineAddLiquidate);
    });

    it("time condition,time Before", async function (){
        // create pool info
        await initCreatePoolInfo(pledgeAddress,minter, 100, 200);
        await busdAddress.connect(minter).approve(pledgeAddress.address, BigInt(2000*1e18));
        // deposit lend
        await pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18));
        // check info
        let num = await pledgeAddress.userLendInfo(minter.address,0);
        expect(num[0]).to.be.equal(BigInt(1000000000000000000000).toString());
        await increase(100000);
        expect(pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18))).to.revertedWith("Less than this time");
    });

    it("time condition, time before", async function (){
       // create pool info
        await initCreatePoolInfo(pledgeAddress,minter, 100, 200);
        await busdAddress.connect(minter).approve(pledgeAddress.address, BigInt(2000*1e18));
        // deposit lend
        await pledgeAddress.connect(minter).depositLend(0, BigInt(1000*1e18));
        // check info
        let num = await pledgeAddress.userLendInfo(minter.address,0);
        expect(num[0]).to.be.equal(BigInt(1000000000000000000000).toString());
        // claim
        expect(pledgeAddress.connect(minter).claimLend(0)).to.revertedWith("Greate than this time");

    });

})




