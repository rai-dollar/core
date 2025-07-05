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
    const deviationThreshold = hre.ethers.BigNumber.from(dec(1, 16));  // 1%

    // staleness threshold for the price feeds
    const stalenessThreshold = {
        chainlink: TimeValues.SECONDS_IN_ONE_DAY,  // 24hr staleness
        api3: TimeValues.SECONDS_IN_ONE_DAY,  // 24hr staleness
        tellor: TimeValues.SECONDS_IN_ONE_DAY,  // 24hr staleness
    }
    const oracleConfigType = "OracleConfig(address primaryOracle, address fallbackOracle, uint256 primaryStalenessThreshold, uint256 fallbackStalenessThreshold)";
    const stethMarketOracleConfig = {
        primaryOracle: chainlinkOracles.stEthUsd,
        fallbackOracle: hre.ethers.constants.AddressZero,
        primaryStalenessThreshold: stalenessThreshold.chainlink,
        fallbackStalenessThreshold: stalenessThreshold.chainlink
    }

    const ethUsdOracleConfig = {
        primaryOracle: chainlinkOracles.ethUsd,
        fallbackOracle: api3Oracles.ethUsd,
        primaryStalenessThreshold: stalenessThreshold.chainlink,
        fallbackStalenessThreshold: stalenessThreshold.api3
    }

    let mockedMarketOracleConfig;
    let mockedEthUsdOracleConfig;

    let wstEthPriceFeed;
    let mockedWstEthPriceFeed;

    before(async () => {
        const chainId = await hre.network.provider.send("eth_chainId");
        console.log("Chain ID:", parseInt(chainId, 16));

        const deployerWallet = (await ethers.getSigners())[0];
        const deployerWalletAddress = deployerWallet.address;

        const MockWSTETHPriceFeedFactory = await ethers.getContractFactory("MockAggregator", deployerWallet);
        const MockApi3Aggregator = await ethers.getContractFactory("MockApi3Aggregator", deployerWallet);

        const mockMarketAggregator = await MockWSTETHPriceFeedFactory.deploy();
        const mockEthAggregator = await MockApi3Aggregator.deploy();
        
        //create config for mocked market oracle
        mockedMarketOracleConfig = {
            primaryOracle: mockMarketAggregator.address,
            fallbackOracle: hre.ethers.constants.AddressZero,
            primaryStalenessThreshold: stalenessThreshold.chainlink,
            fallbackStalenessThreshold: stalenessThreshold.chainlink
        }

        //create config for mocked eth usd oracle
        mockedEthUsdOracleConfig = {
            primaryOracle: mockEthAggregator.address,
            fallbackOracle: api3Oracles.ethUsd,
            primaryStalenessThreshold: stalenessThreshold.api3,
            fallbackStalenessThreshold: stalenessThreshold.api3
        }
        

        console.log("Deploying WSTETHPriceFeed...");
        const WSTETHPriceFeedFactory = await ethers.getContractFactory("WSTETHPriceFeed", deployerWallet);
        // deploy price feeds
        wstEthPriceFeed = await WSTETHPriceFeedFactory.deploy(
            stethMarketOracleConfig,
            ethUsdOracleConfig,
            tokens.wsteth,
            tokens.wsteth,
            deviationThreshold,
            stalenessThreshold.chainlink
        )

        mockedWstEthPriceFeed = await WSTETHPriceFeedFactory.deploy(
            stethMarketOracleConfig,
            mockedEthUsdOracleConfig,
            tokens.wsteth,
            tokens.wsteth,
            deviationThreshold,
            stalenessThreshold.chainlink
        );
        console.log("WSTETHPriceFeed deployed at:", wstEthPriceFeed.address);
    })

    function getPriceWstEthUsdFromReceipt(receipt) {
        const price = receipt.events.filter(event => event.event === "WstEthUsdResponseSaved")[0].args.price;
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
        
        it("should use fallback oracle if primary oracle is stale", async () => {
            const tx = await mockedWstEthPriceFeed.fetchPrice(false);
            const receipt = await tx.wait();
            console.log("receipt", receipt);
            const price = getPriceWstEthUsdFromReceipt(receipt);
            expect(price).to.be.greaterThan(0).and.lessThan(parseFloat(hre.ethers.utils.parseEther("5")));
        });

    })
    
})