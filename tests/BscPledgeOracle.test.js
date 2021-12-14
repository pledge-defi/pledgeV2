const { expect } = require("chai");
const { show } = require("./helper/meta.js");



describe("BscPledgeOracle", function (){
    let bscPledgeOracle;
    let busdAddrress;
    let btcAddress;
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
        await bscPledgeOracle.connect(minter).setPrices([BigInt(parseInt(busdAddrress.address,16)), BigInt(parseInt(btcAddress.address,16))], [100000000,100000000]);
        expect(await bscPledgeOracle.getPrice(busdAddrress.address)).to.equal((BigInt(0).toString()));
        expect(await bscPledgeOracle.getPrice(btcAddress.address)).to.equal((BigInt(0).toString()));
    });

    it("Get price according to INDEX",async function () {
        expect(await bscPledgeOracle.getPrice(busdAddrress.address)).to.equal((BigInt(0).toString()));
        await bscPledgeOracle.connect(minter).setUnderlyingPrice((busdAddrress.address), 100000000);
        expect(await bscPledgeOracle.getUnderlyingPrice(busdAddrress.address)).to.equal((BigInt(100000000).toString()));
    });

    it("Set price according to INDEX", async function (){
        expect(await bscPledgeOracle.getPrice(busdAddrress.address)).to.equal((BigInt(0).toString()));
        await bscPledgeOracle.connect(minter).setUnderlyingPrice((busdAddrress.address), 100000000);
        expect(await bscPledgeOracle.getPrice(busdAddrress.address)).to.equal((BigInt(100000000).toString()));
    });
})