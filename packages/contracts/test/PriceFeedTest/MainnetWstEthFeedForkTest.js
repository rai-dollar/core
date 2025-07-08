const PriceFeed = artifacts.require("contracts/PriceFeeds/PriceFeedTester.sol")
const WSTETHPriceFeed = artifacts.require("contracts/PriceFeeds/WSTETHPriceFeed.sol")
const CompositePriceFeedBase = artifacts.require("contracts/PriceFeeds/CompositePriceFeedBase.sol")
const ChainlinkParser = artifacts.require("contracts/PriceFeeds/ChainlinkParser.sol")
const Api3Parser = artifacts.require("contracts/PriceFeeds/Api3Parser.sol")
const MockAggregator = artifacts.require("contracts/Dependencies/MockAggregator.sol")
const MockTellor = artifacts.require("contracts/Dependencies/MockTellor.sol")
const mainnetConfig = require('../../hardhat.config.mainnet-fork.js');  
const { chainlinkOracles, api3Oracles, tellorOracles, tokens } = require('./oracleAddresses');

const { TestHelper, TimeValues } = require("../../utils/testHelpers.js")
const th = TestHelper

const { dec, assertRevert, toBN } = th

const hre = require("hardhat");
// test with:
// GAS_PRICE=70832172907 npx hardhat test test/PriceFeedTest/MainnetPriceFeedTest.js --config hardhat.config.mainnet-fork.js

contract('WstEthFeedFork', async accounts => {
    const [owner, alice, bob, carol] = accounts;
    const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000)
    // oracles used in the price feeds
    
    // deviation threshold for the price feeds - use ethers BigNumber instead of web3 toBN
    const deviationThreshold = hre.ethers.utils.parseEther("0.01");  // 1%

    // staleness threshold for the price feeds
    const stalenessThreshold = {
        chainlink: TimeValues.SECONDS_IN_ONE_DAY,  // 24hr staleness
        api3: TimeValues.SECONDS_IN_ONE_DAY,  // 24hr staleness
        tellor: TimeValues.SECONDS_IN_ONE_DAY,  // 24hr staleness

    }
    const stethMarketOracleConfig = {
        primaryOracle: chainlinkOracles.stEthUsd,
        fallbackOracle: hre.ethers.constants.AddressZero,
        primaryStalenessThreshold: stalenessThreshold.chainlink,
        fallbackStalenessThreshold: 0
    }

    const ethUsdOracleConfig = {
        primaryOracle: chainlinkOracles.ethUsd,
        fallbackOracle: api3Oracles.ethUsd,
        primaryStalenessThreshold: stalenessThreshold.chainlink,
        fallbackStalenessThreshold: stalenessThreshold.api3
    }

    let mockedMarketOracleConfig;
    let mockedEthUsdOracleConfig;
    let mockChainlinkAggregator1;
    let mockChainlinkAggregator2;
    let mockApi3Aggregator;
    let wstEthPriceFeed;
    let mockedWstEthPriceFeed;

    before(async () => {
        const chainId = await hre.network.provider.send("eth_chainId");
        const block = await hre.network.provider.send("eth_getBlockByNumber", ["latest", false]);
        console.log("Chain ID:", parseInt(chainId, 16));
        console.log("Block timestamp:", block.timestamp);

        const deployerWallet = (await ethers.getSigners())[0];
        const deployerWalletAddress = deployerWallet.address;

        const MockChainlinkAggregator = await ethers.getContractFactory("MockChainlinkAggregator", deployerWallet);
        const MockApi3Aggregator = await ethers.getContractFactory("MockApi3Aggregator", deployerWallet);

        mockChainlinkAggregator1 = await MockChainlinkAggregator.deploy();
        mockChainlinkAggregator2 = await MockChainlinkAggregator.deploy();
        mockApi3Aggregator = await MockApi3Aggregator.deploy();
        
        //create config for mocked market oracle
        mockedMarketOracleConfig = {
            primaryOracle: mockChainlinkAggregator1.address,
            fallbackOracle: hre.ethers.constants.AddressZero,
            primaryStalenessThreshold: stalenessThreshold.chainlink,
            fallbackStalenessThreshold: stalenessThreshold.chainlink
        }

        //create config for mocked eth usd oracle
        mockedEthUsdOracleConfig = {
            primaryOracle: mockChainlinkAggregator2.address,
            fallbackOracle: mockApi3Aggregator.address,
            primaryStalenessThreshold: stalenessThreshold.api3,
            fallbackStalenessThreshold: stalenessThreshold.api3
        }

        const WSTETHPriceFeedFactory = await ethers.getContractFactory("WSTETHPriceFeed", deployerWallet);

        // deploy price feeds
        wstEthPriceFeed = await WSTETHPriceFeedFactory.deploy(
            stethMarketOracleConfig,
            ethUsdOracleConfig,
            tokens.wsteth,
            tokens.wsteth,
            deviationThreshold
        )

        // set mocked oracle prices and timestamps
        await mockChainlinkAggregator1.setPrice(hre.ethers.utils.parseEther("1"));
        await mockChainlinkAggregator1.setTime(block.timestamp);

        await mockChainlinkAggregator2.setPrice(hre.ethers.utils.parseEther("2"));
        await mockChainlinkAggregator2.setTime(block.timestamp);

        await mockApi3Aggregator.setPrice(hre.ethers.utils.parseEther("3"));
        await mockApi3Aggregator.setTime(block.timestamp);

        mockedWstEthPriceFeed = await WSTETHPriceFeedFactory.deploy(
            stethMarketOracleConfig,
            mockedEthUsdOracleConfig,
            tokens.wsteth,
            tokens.wsteth,
            deviationThreshold
        );
        console.log("WSTETHPriceFeed deployed at:", wstEthPriceFeed.address);
    })

    function getPriceWstEthUsdFromReceipt(receipt) {
        const price = receipt.events.filter(event => event.event === "LastGoodResponseUpdated")[0].args.price;
        return parseFloat(hre.ethers.utils.formatEther(price));
    }
    describe("WSTETHPriceFeed", () => {

        it("should get the price of wsteth in usd", async () => {
            // Use fetchPrice instead of getPrice
            const tx = await wstEthPriceFeed.fetchPrice(false);
            const receipt = await tx.wait();
            const price = getPriceWstEthUsdFromReceipt(receipt);
            // Add some assertions
            expect(price).to.be.greaterThan(0).and.lessThan(parseFloat(hre.ethers.utils.parseEther("5")));
        });
        
        it("should use eth/usd fallback oracle if primary oracle is stale", async () => {
            await mockChainlinkAggregator2.setPrice(hre.ethers.utils.parseEther("0"));

            const tx = await mockedWstEthPriceFeed.fetchPrice(false);
            const receipt = await tx.wait();
            const price = getPriceWstEthUsdFromReceipt(receipt);

            const compositeOracleSource = await mockedWstEthPriceFeed.compositePriceSource();
            const marketOracleSource = await mockedWstEthPriceFeed.marketPriceSource();
            const wethUsdOracleSource = await mockedWstEthPriceFeed.wethUsdPriceSource();

            expect(price).to.equal(parseFloat(("3.6228712336164346")));

            expect(compositeOracleSource).to.equal(1);
            expect(marketOracleSource).to.equal(0);
            expect(wethUsdOracleSource).to.equal(0);
        });

    })
    
})