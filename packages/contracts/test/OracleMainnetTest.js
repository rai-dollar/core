const { chainlinkOracles, tokens } = require('../mainnetAddresses.js');

const { TestHelper, TimeValues } = require("../utils/testHelpers.js")
const th = TestHelper

const { dec, assertRevert, toBN } = th

const hre = require("hardhat");
// test with:
// anvil --fork-url https://eth-mainnet.g.alchemy.com/v2/iqmesrxjl-9DUKFsGYB7Xfs0LAPpKv1m --chain-id 31337
// yarn workspace @liquity/contracts hardhat test test/MainnetPriceFeedTest.js --network anvil

contract('OracleMainnetForkTest', async accounts => {
    const [owner, alice, bob, carol] = accounts;
    const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000)
    // oracles used in the price feeds
    
    // deviation threshold for the price feeds - use ethers BigNumber instead of web3 toBN
    const deviationThreshold = hre.ethers.utils.parseEther("0.01");  // 1%

    // staleness threshold for the price feeds
    const stalenessThreshold = TimeValues.SECONDS_IN_ONE_DAY;  // 24hr staleness

    let mockChainlinkAggregator1;
    let mockChainlinkAggregator2;
    let mockApi3Aggregator;
    let wstEthPriceFeed;
    let mockedWstEthPriceFeed;
    let block;

    before(async () => {
        block = await hre.network.provider.send("eth_getBlockByNumber", ["latest", false]);
        const deployerWallet = (await ethers.getSigners())[0];
        const deployerWalletAddress = deployerWallet.address;

        const MockChainlinkAggregator = await ethers.getContractFactory("MockChainlinkAggregator", deployerWallet);

        mockChainlinkAggregator1 = await MockChainlinkAggregator.deploy();
        mockChainlinkAggregator2 = await MockChainlinkAggregator.deploy();
        
        const WSTETHPriceFeedFactory = await ethers.getContractFactory("WSTETHPriceFeed", deployerWallet);

        // deploy price feeds
        wstEthPriceFeed = await WSTETHPriceFeedFactory.deploy(
            chainlinkOracles.ethUsd,
            chainlinkOracles.stEthUsd,
            tokens.wsteth,
            stalenessThreshold,
            stalenessThreshold
        )

        // set mocked oracle prices and timestamps
        await mockChainlinkAggregator1.setPrice(hre.ethers.utils.parseUnits("1", 8));
        await mockChainlinkAggregator1.setUpdateTime(block.timestamp);
        
        mockedWstEthPriceFeed = await WSTETHPriceFeedFactory.deploy(
            chainlinkOracles.ethUsd,
            mockChainlinkAggregator1.address,
            tokens.wsteth,
            stalenessThreshold,
            stalenessThreshold
        );
    })

    describe("WSTETHPriceFeed", () => {

        it("should get the price of wsteth in usd", async () => {
            await wstEthPriceFeed.fetchPrice();
            const price = parseFloat(await wstEthPriceFeed.lastGoodPrice());
            expect(price).to.be.greaterThan(0).and.lessThan(5e21);
        });
        
        it("should use eth/usd x canonical rate if eth/usd oracle is stale", async () => {
            await mockChainlinkAggregator1.setUpdateTime(block.timestamp - (TimeValues.SECONDS_IN_ONE_DAY + 1));
            await mockedWstEthPriceFeed.fetchPrice();

            const state = await mockedWstEthPriceFeed.priceSource();
            const price = parseFloat(await mockedWstEthPriceFeed.lastGoodPrice());

            expect(price).to.be.greaterThan(0).and.lessThan(5e21);; // 1.207805461674524e22
            expect(state).to.be.equal(2);
        });

        it("should use eth/usd x canonical rate if steth/usd oracle returns 0 price", async () => {
            await mockChainlinkAggregator2.setPrice(hre.ethers.utils.parseUnits("0", 8));
            await mockChainlinkAggregator2.setUpdateTime(block.timestamp);
            await mockedWstEthPriceFeed.fetchPrice();
            const state = await mockedWstEthPriceFeed.priceSource();
            const price = parseFloat(await mockedWstEthPriceFeed.lastGoodPrice());
            expect(price).to.be.greaterThan(0).and.lessThan(5e21);; // 1.207805461674524e22
            expect(state).to.be.equal(2);
        });

    })
    
})