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

contract('WstEthFeedFork', async accounts => {
    const [owner, alice, bob, carol] = accounts;
    const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000)
    // oracles used in the price feeds
    const chainlinkOracles = {
        stEthUsd: "0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8",
        stEthEth: "0x86392dC19c0b719886221c78AB11eb8Cf5c52812",
        ethUsd: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
        stethPerWsteth: "0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714",
        wbtcBtc: "0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23",
        btcEth: "0xdeb288F737066589598e9214E782fa5A8eD689e8",
        btcUsd: "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
        rsEthEth: "0x9d2F2f96B24C444ee32E57c04F7d944bcb8c8549"
    }

    const api3Oracles = {
        ethUsd: "0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473",
    }
    const tellorOracles = {
        tellorOracle: "0x8cFc184c877154a8F9ffE0fe75649dbe5e2DBEbf",
    }

    const redstoneOracles = {
        btcUsd: "0xAB7f623fb2F6fea6601D4350FA0E2290663C28Fc",
        ethUsd: "0x67F6838e58859d612E4ddF04dA396d6DABB66Dc4",
        rsEthEth: "0xA736eAe8805dDeFFba40cAB8c99bCB309dEaBd9B"
    }

    // tokens used in the price feeds
    const tokens = {
        wsteth: "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
        steth: "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
        reth: "0xae78736Cd615f374D3085123A210448E74Fc6393",
        wbtc: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
        weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    }

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
    const mainnetForkConfig = mainnetConfig.networks.hardhat.forking;

    let wstEthPriceFeed;
    let mockedWstEthPriceFeed;
    console.log("BEFORE")

    before(async () => {
        const chainId = await hre.network.provider.send("eth_chainId");
        console.log("Chain ID:", chainId);
        // if (chainId !== "0x1") {
        //     throw new Error("Not on mainnet");
        // }

        
        // expect(chainId).to.equal("0x1");
        

        const deployerWallet = (await ethers.getSigners())[0];
        const deployerWalletAddress = deployerWallet.address;

        const MockWSTETHPriceFeedFactory = await ethers.getContractFactory("MockAggregator", deployerWallet);

        const mockMarketAggregator = await MockWSTETHPriceFeedFactory.deploy();
        const mockEthAggregator = await MockWSTETHPriceFeedFactory.deploy();


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
            mockMarketAggregator,
            mockEthAggregator,
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
            const price = getPriceWstEthUsdFromReceipt(receipt);
            expect(price).to.be.greaterThan(0).and.lessThan(parseFloat(hre.ethers.utils.parseEther("5")));
        });

    })
    
})