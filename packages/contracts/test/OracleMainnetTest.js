const { chainlinkOracles, tokens } = require('../mainnetAddresses.js');
const AggregatorV3InterfaceArtifact = require('../artifacts/contracts/v0.8.24/Dependencies/AggregatorV3Interface.sol/AggregatorV3Interface.json');
const MockChainlinkAggregatorArtifact = require('../artifacts/contracts/v0.8.24/TestContracts/MockChainlinkAggregator.sol/MockChainlinkAggregator.json');
const { TestHelper, TimeValues } = require("../utils/testHelpers.js")
const th = TestHelper

const { dec, assertRevert, toBN } = th

const hre = require("hardhat");
// test with:
// anvil --fork-url https://eth-mainnet.g.alchemy.com/v2/iqmesrxjl-9DUKFsGYB7Xfs0LAPpKv1m --chain-id 31337
// yarn workspace @liquity/contracts hardhat test test/MainnetPriceFeedTest.js --network anvil

async function getOraclePrice(oracle) {
    const price = await oracle.latestRoundData();
    return price.answer;
}

contract('WstethMainnetForkTest', async accounts => {
    const [owner, alice, bob, carol] = accounts;
    const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000)
    // oracles used in the price feeds
    
    // deviation threshold for the price feeds - use ethers BigNumber instead of web3 toBN
    const deviationThreshold = hre.ethers.utils.parseEther("0.01");  // 1%

    // staleness threshold for the price feeds
    const stalenessThreshold = TimeValues.SECONDS_IN_ONE_DAY;  // 24hr staleness

    let chainlinkEthUsdOracle;
    let chainlinkStEthUsdOracle;
    let wstEthPriceFeed;
    let block;

    function calculateCanonicalRate(ethUsdPrice, stEthUsdPrice, lstRate) {
        // add 10 digits to price
        const ethUsdPriceWith10Digits = ethUsdPrice * 1e10;
        const stEthUsdPriceWith10Digits = stEthUsdPrice * 1e10;
        const betRate = ethUsdPriceWith10Digits > stEthUsdPriceWith10Digits ? ethUsdPriceWith10Digits : stEthUsdPriceWith10Digits;
        const lstUsdCanonicalPrice = betRate * lstRate / 1e18;

        return parseFloat(lstUsdCanonicalPrice);
    }

    function calculateRate(tokenUsdPrice, lstRate) {
        const tokenUsdPriceWith10Digits = tokenUsdPrice * 1e10;
        const lstUsdCanonicalPrice = tokenUsdPriceWith10Digits * lstRate / 1e18;
        return parseFloat(lstUsdCanonicalPrice);
    }

    async function etchMockChainlinkAggregator(address, artifact) {
        await network.provider.send("hardhat_setCode", [address, artifact.deployedBytecode]);
        const mockedContract = await ethers.getContractAt(artifact.abi, address);
        return mockedContract;
    }

    describe("WSTETHPriceFeed", () => {
        beforeEach(async () => {
        // Reset fork state before each test
        await hre.network.provider.request({
            method: "hardhat_reset",
            params: [
                {
                    forking: {
                        jsonRpcUrl: process.env.MAINNET_RPC_URL || "https://eth-mainnet.g.alchemy.com/v2/iqmesrxjl-9DUKFsGYB7Xfs0LAPpKv1m",
                        // Optional: pin to specific block for consistency
                        blockNumber: 22894418,
                    },
                },
            ],
        });
           
        block = await hre.network.provider.send("eth_getBlockByNumber", ["latest", false]);
        const deployerWallet = (await ethers.getSigners())[0];
        const deployerWalletAddress = deployerWallet.address;

        chainlinkEthUsdOracle = await ethers.getContractAt(AggregatorV3InterfaceArtifact.abi, chainlinkOracles.ethUsd, deployerWallet);
        chainlinkStEthUsdOracle = await ethers.getContractAt(AggregatorV3InterfaceArtifact.abi, chainlinkOracles.stEthUsd, deployerWallet);

        wstEth = await ethers.getContractAt("IWSTETH", tokens.wsteth, deployerWallet);

        
        const WSTETHPriceFeedFactory = await ethers.getContractFactory("WSTETHPriceFeed", deployerWallet);

        // deploy price feeds
        wstEthPriceFeed = await WSTETHPriceFeedFactory.deploy(
            chainlinkOracles.ethUsd,
            chainlinkOracles.stEthUsd,
            tokens.wsteth,
            stalenessThreshold,
            stalenessThreshold
        )
        });

        it("lastGoodPrice should be set on deployment", async () => {
            const price = parseFloat(await wstEthPriceFeed.lastGoodPrice());
            expect(price).to.be.greaterThan(0).and.lessThan(5e21);
        });

        it("should get the price of wsteth in usd", async () => {
            await wstEthPriceFeed.fetchPrice();
            const price = parseFloat(await wstEthPriceFeed.lastGoodPrice());
            const ethUsdPrice = (await chainlinkEthUsdOracle.latestRoundData()).answer;
            const stEthUsdPrice = (await chainlinkStEthUsdOracle.latestRoundData()).answer;
            const canonicalRate = await wstEth.stEthPerToken();
            const canonicalPrice = calculateRate(stEthUsdPrice, canonicalRate);
            expect(price).to.be.equal(canonicalPrice);
        });
        
        it("should use eth/usd x canonical rate if steth/usd oracle is stale", async () => {
            // etch chainlink wsteth oracle with mock chainlink aggregator
            chainlinkStEthUsdOracle = await etchMockChainlinkAggregator(chainlinkOracles.stEthUsd, MockChainlinkAggregatorArtifact);
            await chainlinkStEthUsdOracle.setUpdateTime(block.timestamp - (TimeValues.SECONDS_IN_ONE_DAY + 1));
            await wstEthPriceFeed.fetchPrice();

            const priceSource = await wstEthPriceFeed.priceSource();
            const price = parseFloat(await wstEthPriceFeed.lastGoodPrice());
            const ethUsdPrice = (await chainlinkEthUsdOracle.latestRoundData()).answer;
            const canonicalRate = await wstEth.stEthPerToken();

            const calculatedPrice = calculateRate(ethUsdPrice, canonicalRate);
            const expectedPrice = calculatedPrice > price ? calculatedPrice : price;

            expect(price).to.be.equal(expectedPrice);
            expect(priceSource).to.be.equal(2);
        });

        it("should use eth/usd x canonical rate if steth/usd oracle returns 0 price", async () => {
            chainlinkStEthUsdOracle = await etchMockChainlinkAggregator(chainlinkOracles.stEthUsd, MockChainlinkAggregatorArtifact);
            await chainlinkStEthUsdOracle.setPrice(hre.ethers.utils.parseUnits("0", 8));
            await chainlinkStEthUsdOracle.setUpdateTime(block.timestamp);
            await wstEthPriceFeed.fetchPrice();
            const state = await wstEthPriceFeed.priceSource();
            const price = parseFloat(await wstEthPriceFeed.lastGoodPrice());
            // calculate price from eth/usd x canonical rate
            const ethUsdPrice = (await chainlinkEthUsdOracle.latestRoundData()).answer;
            const canonicalRate = await wstEth.stEthPerToken();
            const calculatedPrice = calculateRate(ethUsdPrice, canonicalRate);
            const expectedPrice = calculatedPrice > price ? calculatedPrice : price;

            expect(price).to.be.equal(expectedPrice);
            expect(state).to.be.equal(2);
        });

    })
    
})