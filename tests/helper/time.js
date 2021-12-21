
const BN = web3.utils.BN;
async function latestBlock () {
  const block = await web3.eth.getBlock('latest');
  return new BN(block.number);
}

async function latestBlockNum () {
  const block = await web3.eth.getBlock('latest');
  return (new BN(block.number)).toNumber();
}


async function showBlock () {
    const block = await web3.eth.getBlock('latest');
    console.log("Block number: " + new BN(block.number).toString());
  }

async function showBlock (msg) {
    const block = await web3.eth.getBlock('latest');
    console.log(msg + " at block number: " + new BN(block.number).toString());
  }

async function stopAutoMine() {
    //stop auto mine or it will mess the block number
    network.provider.send("evm_setIntervalMining", [600000])
    // await network.provider.send("evm_setAutomine", [false])
}

function advanceBlock () {
  // return network.provider.send("evm_mine", [new Date().getTime()])
  return network.provider.send("evm_mine", [])
}


// Advance the block to the passed height
async function advanceBlockTo (target) {
    // stop interval mint,set to 600s
  await stopAutoMine()
  if (!BN.isBN(target)) {
    target = new BN(target);
  }

  const currentBlock = (await latestBlock());
  const start = Date.now();
  let notified;
  if (target.lt(currentBlock)) throw Error(`Target block #(${target}) is lower than current block #(${currentBlock})`);
  while ((await latestBlock()).lt(target)) {
    if (!notified && Date.now() - start >= 5000) {
      notified = true;
      console.log(`\
${colors.white.bgBlack('@openzeppelin/test-helpers')} ${colors.black.bgYellow('WARN')} advanceBlockTo: Advancing too ` +
      'many blocks is causing this test to be slow.');
    }
    await advanceBlock();
  }
  await showBlock('arrive')
}

// Returns the time of the last mined block in seconds
async function latest () {
    const block = await web3.eth.getBlock('latest');
    return new BN(block.timestamp);
  }

async function increase(seconds) {
  await network.provider.send("evm_increaseTime", [seconds])
  await advanceBlock();
}


module.exports = {
    advanceBlockTo,
    advanceBlock,
    latestBlock,
    latestBlockNum,
    showBlock,
    stopAutoMine,
    latest,
    increase
};