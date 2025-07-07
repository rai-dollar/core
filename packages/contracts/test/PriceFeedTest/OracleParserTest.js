const { chainlinkOracles, api3Oracles, tellorOracles, redstoneOracles, tokens } = require('./oracleAddresses');

const { TestHelper, TimeValues } = require("../../utils/testHelpers.js")
const th = TestHelper

const { dec, assertRevert, toBN } = th

const hre = require("hardhat");
// test with:
// GAS_PRICE=70832172907 npx hardhat test test/PriceFeedTest/MainnetPriceFeedTest.js --config hardhat.config.mainnet-fork.js

contract('OracleParserTest', async accounts => {
    const [deployerWallet, alice, bob, carol] = accounts;
    const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000)

    let parserTester;

    before(async () => {
        const chainId = await hre.network.provider.send("eth_chainId");
        console.log("Chain ID:", parseInt(chainId, 16));

        // deploy parser tester
        const ParserTesterFactory = await ethers.getContractFactory("ParserTester", deployerWallet);
        parserTester = await ParserTesterFactory.deploy(chainlinkOracles.ethUsd, api3Oracles.ethUsd, redstoneOracles.ethUsd, tellorOracles.tellorOracle);
    })
    function getPriceFromLogs(receipt, eventName) {
        const price = receipt.events.find(log => log.event === eventName).args.price;
        const lastUpdated = receipt.events.find(log => log.event === eventName).args.lastUpdated;
        return { price: parseInt(price), lastUpdated: parseInt(lastUpdated) };
    }
    describe("ParserTester", () => {
        it("should get the price of stEthUsd from chainlink", async () => {
            const tx = await parserTester.testChainlinkParser();
            const receipt = await tx.wait(); 
            const { price, lastUpdated } = getPriceFromLogs(receipt, "ChainlinkResponse");

            expect(price).to.be.greaterThan(0).and.lessThan(parseFloat(hre.ethers.utils.parseEther("5000")));
            expect(lastUpdated).to.be.greaterThan(0).and.lessThan(Date.now() / 1000);
        })

        it("should get the price of ethUsd from api3", async () => {
            const tx = await parserTester.testApi3Parser();
            const receipt = await tx.wait();
            const { price, lastUpdated } = getPriceFromLogs(receipt, "Api3Response");

            expect(price).to.be.greaterThan(0).and.lessThan(parseFloat(hre.ethers.utils.parseEther("5000")));
            expect(lastUpdated).to.be.greaterThan(0).and.lessThan(Date.now() / 1000);
        })

        it("should get the price of ethUsd from redstone", async () => {
            const tx = await parserTester.testRedstoneParser();
            const receipt = await tx.wait();
            const { price, lastUpdated } = getPriceFromLogs(receipt, "RedstoneResponse");

            expect(price).to.be.greaterThan(0).and.lessThan(parseFloat(hre.ethers.utils.parseEther("5000")));
            expect(lastUpdated).to.be.greaterThan(0).and.lessThan(Date.now() / 1000);
        })

        it("should get the price of ethUsd from tellor", async () => {  
            const tx = await parserTester.testTellorParser();
            const receipt = await tx.wait();
            const { price, lastUpdated } = getPriceFromLogs(receipt, "TellorResponse");
            expect(price).to.be.greaterThan(0).and.lessThan(parseFloat(hre.ethers.utils.parseEther("5000")));
            expect(lastUpdated).to.be.greaterThan(0).and.lessThan(Date.now() / 1000);
        })
    })
})