const { chainlinkOracles, tokens } = require('../mainnetAddresses.js');
const AggregatorV3InterfaceArtifact = require('../artifacts/contracts/v0.8.24/Dependencies/AggregatorV3Interface.sol/AggregatorV3Interface.json');
const MockChainlinkAggregatorArtifact = require('../artifacts/contracts/v0.8.24/TestContracts/MockChainlinkAggregator.sol/MockChainlinkAggregator.json');
const MockWSTETHArtifact = require('../artifacts/contracts/v0.8.24/TestContracts/MockWSTETH.sol/MockWSTETH.json');
const { TestHelper, TimeValues } = require("../utils/testHelpers.js")
const th = TestHelper
const { BigNumber } = require("ethers");
const { dec, assertRevert, toBN } = th

const hre = require("hardhat");
// test with:
// anvil --fork-url https://eth-mainnet.g.alchemy.com/v2/iqmesrxjl-9DUKFsGYB7Xfs0LAPpKv1m --chain-id 31337
// yarn workspace @liquity/contracts hardhat test test/MainnetPriceFeedTest.js --network anvil

async function getOraclePrice(oracle) {
    const price = await oracle.latestRoundData();
    return price.answer;
}

function getEvent(receipt, eventName) {
    const event = receipt.events.find(log => log.event === eventName);
    return event;
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
        const ethUsdPriceWith10Digits = ethUsdPrice.mul(BigNumber.from(dec(1,10)));
        const stEthUsdPriceWith10Digits = stEthUsdPrice.mul(BigNumber.from(dec(1,10)));
        const betRate = ethUsdPriceWith10Digits.gt(stEthUsdPriceWith10Digits) ? ethUsdPriceWith10Digits : stEthUsdPriceWith10Digits;
        const lstUsdCanonicalPrice = betRate.mul(lstRate).div(BigNumber.from(dec(1,18)));

        return lstUsdCanonicalPrice;
    }

    function calculateRate(tokenUsdPrice, lstRate) {
        // scale up tokenUsdPrice by 10 digits
        const tokenUsdPriceWith10Digits = tokenUsdPrice.mul(BigNumber.from(dec(1,10)));
        const lstUsdCanonicalPrice = tokenUsdPriceWith10Digits.mul(lstRate).div(BigNumber.from(dec(1,18)));
        return lstUsdCanonicalPrice;
    }

    async function etchContract(address, artifact) {
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
        async function getPrice(oracle) {
            const price = await oracle.latestRoundData();
            return price.answer;
        }
        it.skip("WstethPriceFeed: lastGoodPrice should be set on deployment", async () => {
            const price = await wstEthPriceFeed.lastGoodPrice();
            expect(price.gt(BigNumber.from(dec(0,18)))).to.be.true;
            expect(price.lt(BigNumber.from(dec(5,21)))).to.be.true;
        });

        it.skip("WstethPriceFeed: should get the price of wsteth in usd", async () => {
            await wstEthPriceFeed.fetchPrice();
            const price = await wstEthPriceFeed.lastGoodPrice();
            const stEthUsdPrice = (await chainlinkStEthUsdOracle.latestRoundData()).answer;
            const canonicalRate = await wstEth.stEthPerToken(); 
            const canonicalPrice = calculateRate(stEthUsdPrice, canonicalRate);
            expect(price.eq(canonicalPrice)).to.be.true;
        });
        
        it.skip("WstethPriceFeed: should use eth/usd x canonical rate if steth/usd oracle is stale", async () => {
            // etch chainlink wsteth oracle with mock chainlink aggregator
            chainlinkStEthUsdOracle = await etchContract(chainlinkOracles.stEthUsd, MockChainlinkAggregatorArtifact);
            await chainlinkStEthUsdOracle.setUpdateTime(block.timestamp - (TimeValues.SECONDS_IN_ONE_DAY + 1));
            await wstEthPriceFeed.fetchPrice();

            const priceSource = await wstEthPriceFeed.priceSource();
            const lastGoodPrice = await wstEthPriceFeed.lastGoodPrice();

            const ethUsdPrice = (await chainlinkEthUsdOracle.latestRoundData()).answer;
            const canonicalRate = await wstEth.stEthPerToken();

            const calculatedPrice = calculateRate(ethUsdPrice, canonicalRate);
            const expectedPrice = calculatedPrice.gt(lastGoodPrice) ? calculatedPrice : lastGoodPrice;

            expect(lastGoodPrice.eq(expectedPrice)).to.be.true;
            expect(priceSource).to.equal(2);
        });

        it.skip("WstethPriceFeed: should use eth/usd x canonical rate if steth/usd oracle returns 0 price", async () => {
            chainlinkStEthUsdOracle = await etchContract(chainlinkOracles.stEthUsd, MockChainlinkAggregatorArtifact);
            await chainlinkStEthUsdOracle.setPrice(hre.ethers.utils.parseUnits("0", 8));
            await chainlinkStEthUsdOracle.setUpdateTime(block.timestamp);
            await wstEthPriceFeed.fetchPrice();

            const priceSource = await wstEthPriceFeed.priceSource();
            const lastGoodPrice = await wstEthPriceFeed.lastGoodPrice();

            const ethUsdPrice = (await chainlinkEthUsdOracle.latestRoundData()).answer;
            const canonicalRate = await wstEth.stEthPerToken();
            const calculatedPrice = calculateRate(ethUsdPrice, canonicalRate);
            const expectedPrice = calculatedPrice.gt(lastGoodPrice) ? calculatedPrice : lastGoodPrice;

            expect(lastGoodPrice.eq(expectedPrice)).to.be.true;
            expect(priceSource).to.equal(2);
        });

        it.skip("WstethPriceFeed: should have correct stored staleness for chainlink steth/usd oracle", async () => {
            const oracle = await wstEthPriceFeed.stEthUsdOracle();
            expect(oracle.stalenessThreshold.eq(BigNumber.from(TimeValues.SECONDS_IN_ONE_DAY))).to.be.true;
        });

        it.skip("WstethPriceFeed: should have correct stored staleness for chainlink eth/usd oracle", async () => {
            const oracle = await wstEthPriceFeed.ethUsdOracle();
            expect(oracle.stalenessThreshold.eq(BigNumber.from(stalenessThreshold))).to.be.true;
        });



        it.skip("WstethPriceFeed: price source should be lastGoodPrice and should return lastGoodPrice when exchange rate fails", async () => {
            await wstEthPriceFeed.fetchPrice();
            const lastGoodPrice = await wstEthPriceFeed.lastGoodPrice();
            wstEth = await etchContract(tokens.wsteth, MockWSTETHArtifact);

            const tx = await wstEthPriceFeed.fetchPrice();
            const receipt = await tx.wait.skip();
            const event = getEvent(receipt, "ShutDownFromOracleFailure");

            const priceSource = await wstEthPriceFeed.priceSource();
            const priceAfterFailure = await wstEthPriceFeed.lastGoodPrice();

            expect(priceSource).to.equal(2);
            expect(event).to.exist;
            expect(lastGoodPrice.eq(priceAfterFailure)).to.be.true;
        });

        it.skip("WstethPriceFeed: price source should be lastGoodPrice and should return lastGoodPrice when Eth/USD oracle isStale", async () => {
            await wstEthPriceFeed.fetchPrice();
            const price1 = await wstEthPriceFeed.lastGoodPrice();
            const priceSource1 = await wstEthPriceFeed.priceSource();
            expect(price1.gt(BigNumber.from(0))).to.be.true;
            expect(priceSource1).to.equal(0);

            chainlinkEthUsdOracle = await etchContract(chainlinkOracles.ethUsd, MockChainlinkAggregatorArtifact);
            const staleTime = block.timestamp - (TimeValues.SECONDS_IN_ONE_DAY + 1);
            await chainlinkEthUsdOracle.setUpdateTime(staleTime);
            const roundData = await chainlinkEthUsdOracle.latestRoundData();
            expect(roundData.updatedAt.eq(BigNumber.from(staleTime))).to.be.true;

            await wstEthPriceFeed.fetchPrice();
            const price2 = await wstEthPriceFeed.lastGoodPrice();
            const priceSource2 = await wstEthPriceFeed.priceSource();
            expect(price2.eq(price1)).to.be.true;
            expect(priceSource2).to.equal(2);
        });

        it.skip("WstethPriceFeed: price source should be lastGoodPrice and should return lastGoodPrice when Eth/USD oracle returns 0 price", async () => {
            await wstEthPriceFeed.fetchPrice();
            const price1 = await wstEthPriceFeed.lastGoodPrice();
            const priceSource1 = await wstEthPriceFeed.priceSource();
            expect(price1.gt(BigNumber.from(0))).to.be.true;
            expect(priceSource1).to.equal(0);

            chainlinkEthUsdOracle = await etchContract(chainlinkOracles.ethUsd, MockChainlinkAggregatorArtifact);
            await chainlinkEthUsdOracle.setPrice(hre.ethers.utils.parseUnits("0", 8));
            await chainlinkEthUsdOracle.setUpdateTime(block.timestamp);
            const roundData = await chainlinkEthUsdOracle.latestRoundData();
            expect(roundData.answer.eq(BigNumber.from(0))).to.be.true;

            await wstEthPriceFeed.fetchPrice();
            const price2 = await wstEthPriceFeed.lastGoodPrice();
            const priceSource2 = await wstEthPriceFeed.priceSource();
            expect(price2.eq(price1)).to.be.true;
            expect(priceSource2).to.equal(2);
        });

        it("WstethPriceFeed: fetch price should return min ETHUSD x canonical rate or lastGoodPrice when Steth/usd oracle is stale and price source should be ETHUSDXCanonicalRate", async () => {
            const stethBeforeFailure = (await chainlinkStEthUsdOracle.latestRoundData()).answer;
            await wstEthPriceFeed.fetchPrice();
            const price1 = await wstEthPriceFeed.lastGoodPrice();
            const priceSource1 = await wstEthPriceFeed.priceSource();
            expect(price1.gt(BigNumber.from(0))).to.be.true;
            expect(priceSource1).to.be.equal(0);


            chainlinkStEthUsdOracle = await etchContract(chainlinkOracles.stEthUsd, MockChainlinkAggregatorArtifact);
            const staleTime = block.timestamp - (TimeValues.SECONDS_IN_ONE_DAY + 1);
            await chainlinkStEthUsdOracle.setUpdateTime(staleTime);
            const roundData = await chainlinkStEthUsdOracle.latestRoundData();
            expect(roundData.updatedAt.eq(BigNumber.from(staleTime))).to.be.true;

            const tx = await wstEthPriceFeed.fetchPrice();
            const receipt = await tx.wait.skip();

            const event = getEvent(receipt, "ShutDownFromOracleFailure");
            expect(event).to.exist;
            // assert that oracle did fail
            const priceSource2 = await wstEthPriceFeed.priceSource();

            expect(priceSource2).to.equal(1);

            const lastGoodAfterFailure = await wstEthPriceFeed.lastGoodPrice();

            const ethUsdPrice = (await chainlinkEthUsdOracle.latestRoundData()).answer;
            const canonicalRate = await wstEth.stEthPerToken();
            const calculatedPrice = calculateRate(ethUsdPrice, canonicalRate);
            const expectedPrice = calculatedPrice.lt(lastGoodAfterFailure) ? calculatedPrice : lastGoodAfterFailure;

            expect(lastGoodAfterFailure.eq(expectedPrice)).to.be.true;
        });
    });
    
})