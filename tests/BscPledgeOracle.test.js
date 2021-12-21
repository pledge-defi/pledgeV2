const { expect } = require("chai");
const { show } = require("./helper/meta.js");
const BN = require('bn.js');


describe("BscPledgeOracle", function (){
    let bscPledgeOracle, busdAddrress,btcAddress;
    beforeEach(async ()=>{
        [minter, alice, bob, carol, _] = await ethers.getSigners();
        const bscPledgeOracleToken = await ethers.getContractFactory("BscPledgeOracle");
        bscPledgeOracle = await bscPledgeOracleToken.deploy();
        const busdToken = await ethers.getContractFactory("BEP20Token");
        busdAddrress = await busdToken.deploy();
        const btcToken = await ethers.getContractFactory("BtcToken");
        btcAddress = await btcToken.deploy();
    });

    it ("can not set price without authorization", async function() {
        await expect(bscPledgeOracle.connect(alice).setPrice(busdAddrress.address, 100000)).to.be.revertedWith("Ownable: caller is not the owner");
      });

    it ("Admin set price operation", async function (){
        expect(await bscPledgeOracle.getPrice(busdAddrress.address)).to.equal((BigInt(0).toString()));
        await bscPledgeOracle.connect(minter).setPrice(busdAddrress.address, 100000000);
        expect(await bscPledgeOracle.getPrice(busdAddrress.address)).to.equal((BigInt(100000000).toString()));
    });

    it("Administrators set prices in batches", async function (){
        expect(await bscPledgeOracle.getPrice(busdAddrress.address)).to.equal((BigInt(0).toString()));
        expect(await bscPledgeOracle.getPrice(btcAddress.address)).to.equal((BigInt(0).toString()));
        let busdIndex = new BN((busdAddrress.address).substring(2),16).toString(10);
        let btcIndex = new BN((btcAddress.address).substring(2),16).toString(10);
        await bscPledgeOracle.connect(minter).setPrices([busdIndex,btcIndex],[100,100]);
        expect(await bscPledgeOracle.getUnderlyingPrice(0)).to.equal((BigInt(100).toString()));
        expect(await bscPledgeOracle.getUnderlyingPrice(1)).to.equal((BigInt(100).toString()));
    });

    it("Get price according to INDEX",async function () {
        expect(await bscPledgeOracle.getPrice(busdAddrress.address)).to.equal((BigInt(0).toString()));
        let underIndex = new BN((busdAddrress.address).substring(2),16).toString(10);
        await bscPledgeOracle.connect(minter).setUnderlyingPrice(underIndex, 100000000);
        expect(await bscPledgeOracle.getUnderlyingPrice(underIndex)).to.equal((BigInt(100000000).toString()));
    });

    it("Set price according to INDEX", async function (){
        expect(await bscPledgeOracle.getPrice(busdAddrress.address)).to.equal((BigInt(0).toString()));
        let underIndex = new BN((busdAddrress.address).substring(2),16).toString(10);
        await bscPledgeOracle.connect(minter).setUnderlyingPrice(underIndex, 100000000);
        expect(await bscPledgeOracle.getPrice(busdAddrress.address)).to.equal((BigInt(100000000).toString()));
    });

    it("Set AssetsAggregator", async function (){
        let arrData = await bscPledgeOracle.getAssetsAggregator(busdAddrress.address)
        show(arrData[0]);
        expect(arrData[0]).to.equal('0x0000000000000000000000000000000000000000');
        await bscPledgeOracle.connect(minter).setAssetsAggregator(busdAddrress.address,btcAddress.address,18);
        let data = await bscPledgeOracle.getAssetsAggregator(busdAddrress.address);
        expect(data[0]).to.equal((btcAddress.address));
        expect(data[1]).to.equal(18);
    });



})