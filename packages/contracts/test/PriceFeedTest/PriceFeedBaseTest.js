const PriceFeed = artifacts.require("contracts/PriceFeeds/PriceFeedTester.sol")
const WSTETHPriceFeed = artifacts.require("contracts/PriceFeeds/WSTETHPriceFeed.sol")
const CompositePriceFeedBase = artifacts.require("contracts/PriceFeeds/CompositePriceFeedBase.sol")
const ChainlinkParser = artifacts.require("contracts/PriceFeeds/ChainlinkParser.sol")
const Api3Parser = artifacts.require("contracts/PriceFeeds/Api3Parser.sol")
const MockAggregator = artifacts.require("contracts/Dependencies/MockAggregator.sol")
const MockTellor = artifacts.require("contracts/Dependencies/MockTellor.sol")
const mainnetConfig = require('../../hardhat.config.mainnet-fork.js');

const { TestHelper, TimeValues } = require("../../utils/testHelpers.js")
const th = TestHelper

const { dec, assertRevert, toBN } = th

const hre = require("hardhat");
// test with:
// GAS_PRICE=70832172907 npx hardhat test test/PriceFeedTest/MainnetPriceFeedTest.js --config hardhat.config.mainnet-fork.js

contract('PriceFeedUnitTests', async accounts => {
    const [owner, alice, bob, carol] = accounts;
    const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000)

    // deviation threshold for the price feeds - use ethers BigNumber instead of web3 toBN
    const deviationThreshold = hre.ethers.BigNumber.from(dec(1, 16));  // 1%

    // staleness threshold for the price feeds
    const stalenessThreshold = {
        chainlink: TimeValues.SECONDS_IN_ONE_DAY,  // 24hr staleness
        api3: TimeValues.SECONDS_IN_ONE_DAY,  // 24hr staleness
        tellor: TimeValues.SECONDS_IN_ONE_DAY,  // 24hr staleness
    }
    const oracleConfigType = "OracleConfig(address primaryOracle, address fallbackOracle, uint256 primaryStalenessThreshold, uint256 fallbackStalenessThreshold)";
     
    let mockMarketAggregator;
    let mockFallbackAggregator;

    let mockWstETH;

    let priceFeedBase;

    let blockTimestamp;
    console.log("BEFORE")

    before(async () => {

        blockTimestamp = await hre.ethers.provider.getBlock("latest").then(block => block.timestamp);
        const deployerWallet = (await ethers.getSigners())[0];

        const MockChainlinkAggregator = await ethers.getContractFactory("MockChainlinkAggregator", deployerWallet);
        const MockApi3Aggregator = await ethers.getContractFactory("MockApi3Aggregator", deployerWallet);

        mockMarketAggregator = await MockChainlinkAggregator.deploy();
        mockFallbackAggregator = await MockApi3Aggregator.deploy();

        const MockWstETH = await ethers.getContractFactory("MockWstETH", deployerWallet);
        mockWstETH = await MockWstETH.deploy();

        // set chainlink price to 8 decimals and api3 to 18 decimals
        mockMarketAggregator.setPrice(hre.ethers.utils.parseUnits("1000", 8));
        mockFallbackAggregator.setPrice(hre.ethers.utils.parseUnits("2000", 18));

        // set last updated time to 100 seconds ago
        mockMarketAggregator.setUpdateTime(blockTimestamp - 100);
        mockFallbackAggregator.setUpdateTime(blockTimestamp - 100);

        mockMarketAggregator.setDecimals(8);
        mockFallbackAggregator.setDecimals(18);

        const stalenessThreshold = 1000;

        const marketOracleConfig = {
            primaryOracle: mockMarketAggregator.address,
            fallbackOracle: mockFallbackAggregator.address,
            primaryStalenessThreshold: stalenessThreshold,
            fallbackStalenessThreshold: stalenessThreshold
        }
        // get block timestamp
        const block = await hre.ethers.provider.getBlock("latest");
        blockTimestamp = block.timestamp;

        const priceFeedBaseFactory = await ethers.getContractFactory("PriceFeedBaseTester", deployerWallet);

        priceFeedBase = await priceFeedBaseFactory.deploy(
            marketOracleConfig,
            mockWstETH.address,
            deviationThreshold
        );

    })

    function getPriceFromReceipt(receipt) {
        const price = receipt.events.filter(event => event.event === "LastGoodMarketResponseUpdated")[0].args.price;
        return parseFloat(hre.ethers.utils.formatEther(price));
    }

    function getLastUpdatedFromReceipt(receipt) {
        const lastUpdated = receipt.events.filter(event => event.event === "LastGoodMarketResponseUpdated")[0].args.lastUpdated;
        return lastUpdated;
    }

    function getPriceEmittedFromReceipt(receipt) {
        const price = receipt.events.filter(event => event.event === "PriceEmitted")[0].args.price;
        return parseFloat(hre.ethers.utils.formatEther(price));
    }

    function getEventFromReceipt(receipt, logString) {
        const log = receipt.events.filter(log => log.event === logString)[0];
        return log;
    }

    describe("PriceFeedBase", () => {

        it("should get the primary oracle price", async () => {
            const tx = await priceFeedBase.fetchPrice(false);
            const receipt = await tx.wait();
            const price = getPriceFromReceipt(receipt);
            expect(parseFloat(price)).to.equal(1000);
        });
        
        it("should use fallback oracle if primary oracle is stale", async () => {
            mockMarketAggregator.setUpdateTime(blockTimestamp - 1000);
            const tx = await priceFeedBase.fetchPrice(false);
            const receipt = await tx.wait();
            const price = getPriceFromReceipt(receipt);
            expect(parseFloat(price)).to.equal(2000);
        });

        it("should use last good response if both oracles are stale", async () => {
            mockMarketAggregator.setUpdateTime(blockTimestamp - 1000);
            mockFallbackAggregator.setUpdateTime(blockTimestamp - 1000);
            const tx = await priceFeedBase.fetchPrice(false);
            const receipt = await tx.wait();
            const priceSource = getEventFromReceipt(receipt, "MarketPriceSourceChanged");
            expect(priceSource.args.marketPriceSource).to.equal(2);
        });

    })
    
})