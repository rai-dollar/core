const { expect } = require("chai");
const { BN } = require("@openzeppelin/test-helpers");
const { ethers } = require("hardhat");

const testHelpers = require("../utils/testHelpers.js");

const th = testHelpers.TestHelper;
const assertRevert = th.assertRevert;

const RDOracle = artifacts.require("./RDOracle.sol");
const Vault = artifacts.require("./Vendor/@balancer-labs/v3-vault/contracts/Vault.sol");
const StablePoolFactory = artifacts.require(
  "./Vendor/@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol"
);
const ERC20 = artifacts.require("@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20");

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const DEFAULT_AMP_FACTOR = 1000;
const BASE_MIN_SWAP_FEE = 1e12; // 0.001% (in WAD)

const TokenType = {
  STANDARD: 0,
  WITH_RATE: 1
};

/**
 * Helper function to create a TokenConfig array for Truffle.
 * @param {string} tokenAddress The address of the ERC20 token.
 * @param {number} tokenType The type of the token (TokenType.STANDARD or TokenType.WITH_RATE).
 * @param {string} rateProvider The address of the rate provider.
 * @param {boolean} paysYieldFees Whether the token pays yield fees.
 * @returns {Array} The TokenConfig as an array [token, tokenType, rateProvider, paysYieldFees].
 */
function createTruffleTokenConfig(
  tokenAddress,
  tokenType = TokenType.STANDARD,
  rateProvider = ethers.constants.AddressZero,
  paysYieldFees = false
) {
  return [tokenAddress, tokenType, rateProvider, paysYieldFees];
}

contract("RDOracle", async accounts => {
  let rdToken, USDC, USDT, DAI, stablecoins;
  let vault, rdOracle, stablePoolFactory; // Declare rdOracle at contract level

  const QUOTE_PERIOD_FAST = 300; // 5 minutes
  const QUOTE_PERIOD_SLOW = 3600; // 1 hour
  const MIN_OBSERVATION_DELTA = 60; // 1 minute

  const USDCAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"; // 6 decimals
  const USDTAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7"; // 6 decimals
  const DAIAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F"; // 18 decimals

  const RDTAddress = "0x01420eC851Ad4202894BEA0D48dE097dEeadc1a8"; // 18 decimals

  const anvilAccount1 = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";

  const balv3StablePoolFactory = "0xB9d01CA61b9C181dA1051bFDd28e1097e920AB14";
  const balv3Vault = "0xbA1333333333a1BA1108E8412f11850A5C319bA9";

  const logPool = false;

  beforeEach(async () => {
    USDC = await ERC20.at(USDCAddress);
    USDT = await ERC20.at(USDTAddress);
    DAI = await ERC20.at(DAIAddress);
    RD = await ERC20.at(RDTAddress);

    // rdToken = await ERC20.new("RAI Dollar", "RD");
    stablecoins = [USDC.address, USDT.address, DAI.address];

    vault = await Vault.at(balv3Vault);

    rdOracle = await RDOracle.new(
      vault.address,
      RD.address,
      QUOTE_PERIOD_FAST,
      QUOTE_PERIOD_SLOW,
      stablecoins,
      MIN_OBSERVATION_DELTA
    );

    stablePoolFactory = await StablePoolFactory.at(balv3StablePoolFactory);

    const poolName = "RD-USDC-USDT-DAI";
    const poolSymbol = "RD-USDC-USDT-DAI";

    const truffleTokenConfigs = [
      createTruffleTokenConfig(RDTAddress, TokenType.STANDARD),
      createTruffleTokenConfig(DAIAddress, TokenType.STANDARD),
      createTruffleTokenConfig(USDCAddress, TokenType.STANDARD),
      createTruffleTokenConfig(USDTAddress, TokenType.STANDARD)
    ];

    // Sort the token configurations by token address (the first element of each config array)
    // in ascending order to meet Balancer V3 Vault requirements.
    // const truffleTokenConfigs = [...unsortedTruffleTokenConfigs].sort((configA, configB) => {
    //   const addressA = configA[0].toLowerCase(); // Address is the first element
    //   const addressB = configB[0].toLowerCase();
    //   if (addressA < addressB) {
    //     return -1;
    //   }
    //   if (addressA > addressB) {
    //     return 1;
    //   }
    //   return 0;
    // });

    const amplificationParameter = DEFAULT_AMP_FACTOR;

    const truffleRoleAccounts = [
      anvilAccount1, // pauseManager
      anvilAccount1, // swapFeeManager
      ZERO_ADDRESS // poolCreator
    ];

    const swapFeePercentage = BASE_MIN_SWAP_FEE; // Defined as 1e12
    const poolHookContract_Address = rdOracle.address; // rdOracle instance must be ready
    const enableDonation = false;
    const disableUnbalancedLiquidity = false;
    const randomBytes = ethers.utils.randomBytes(32);
    const salt = ethers.utils.hexlify(randomBytes);

    if (logPool) {
      console.log(`Attempting to create pool with factory: ${stablePoolFactory.address}`);
      console.log(`Parameters for create:`);
      console.log(`  Name: ${poolName}`);
      console.log(`  Symbol: ${poolSymbol}`);
      console.log(`  Token Configs: `, truffleTokenConfigs);
      console.log(`  Amplification: ${amplificationParameter.toString()}`);
      console.log(`  Role Accounts: `, truffleRoleAccounts);
      console.log(`  Swap Fee: ${swapFeePercentage.toString()}`);
      console.log(`  Hook Address: ${poolHookContract_Address}`);
      console.log(`  Salt: ${salt}`);
      console.log(`  Sender (from account): ${anvilAccount1}`);
    }

    try {
      const txResponse = await stablePoolFactory.create(
        poolName,
        poolSymbol,
        truffleTokenConfigs,
        amplificationParameter,
        truffleRoleAccounts,
        swapFeePercentage,
        poolHookContract_Address,
        enableDonation,
        disableUnbalancedLiquidity,
        salt
      );

      if (logPool) {
        console.log("Pool creation transaction sent successfully!");
        console.log("Transaction Hash:", txResponse.tx);
      }

      let newPoolAddress;
      // Iterate over logs to find PoolCreated event (common in Balancer factories)
      if (txResponse.logs) {
        for (const log of txResponse.logs) {
          if (log.event === "PoolCreated" && log.args && log.args.pool) {
            newPoolAddress = log.args.pool;
            break;
          }
        }
      }

      if (newPoolAddress) {
        if (logPool) {
          console.log("New Pool Address via PoolCreated event:", newPoolAddress);
        }
        // You can now interact with the new pool using its address, e.g.:
        // const newPoolInstance = await SomePoolContract.at(newPoolAddress);
      } else {
        if (logPool) {
          console.log(
            "PoolCreated event not found or pool address missing in logs. Check contract events."
          );
        }
        // The pool address might also be deterministically calculable using the factory's GET_POOL_ADDRESS function if available,
        // or might be returned directly by the create function if the ABI specifies it (Truffle would make it available).
        // If the factory's create function returns the address, it would be:
        // const returnedPoolAddress = txResponse; // if .create itself returns the address directly (less common for tx functions)
        // For Truffle, the `txResponse` is an object with tx hash, logs, receipt. The return value of the solidity function is not directly in txResponse.
      }
    } catch (error) {
      console.error("Error creating stable pool:", error);
      // This will provide details if the transaction reverts (e.g., due to contract logic, out of gas, or if the factory contract code isn't at the address on your local chain)
    }
  });

  describe("RDOracle Initialization", () => {
    xit("should initialize with correct parameters", async () => {
      // Check vault address
      expect(await rdOracle.vault()).to.equal(vault.address);
      // Check RD token address
      expect(await rdOracle.rdToken()).to.equal(RDTAddress);
      // Check quote periods
      expect(await rdOracle.quotePeriodFast()).to.be.bignumber.equal(new BN(QUOTE_PERIOD_FAST));
      expect(await rdOracle.quotePeriodSlow()).to.be.bignumber.equal(new BN(QUOTE_PERIOD_SLOW));
      // Check minimum observation delta
      expect(await rdOracle.minObservationDelta()).to.be.bignumber.equal(
        new BN(MIN_OBSERVATION_DELTA)
      );
      // Check stablecoin basket
      const basket = await rdOracle.stablecoinBasket();
      expect(basket).to.have.lengthOf(3);
      expect(basket[0]).to.equal(USDC.address);
      expect(basket[1]).to.equal(USDT.address);
      expect(basket[2]).to.equal(DAI.address);
    });

    xit("should revert if fast period >= slow period", async () => {
      // Try to deploy with fast period equal to slow period
      await assertRevert(
        RDOracle.new(
          vault.address,
          RDTAddress,
          QUOTE_PERIOD_SLOW, // Using slow period as fast period
          QUOTE_PERIOD_SLOW,
          stablecoins,
          MIN_OBSERVATION_DELTA
        ),
        "RDOracle/period-mismatch fast period should be lt slow period"
      );

      // Try to deploy with fast period greater than slow period
      await assertRevert(
        RDOracle.new(
          vault.address,
          RDTAddress,
          QUOTE_PERIOD_SLOW + 100, // Fast period > slow period
          QUOTE_PERIOD_SLOW,
          stablecoins,
          MIN_OBSERVATION_DELTA
        ),
        "RDOracle/period-mismatch fast period should be lt slow period"
      );
    });

    xit("should initialize oracle state with price of 1 RD/USD", async () => {
      // Get the initial sqrtPriceX96 value (2^96 for price of 1)
      const expectedSqrtPriceX96 = new BN("2").pow(new BN("96"));
      const oracleState = await rdOracle.oracleState();
      expect(oracleState.sqrtPriceX96).to.be.bignumber.equal(expectedSqrtPriceX96);
    });

    xit("should initialize oracle with proper symbol", async () => {
      expect(await rdOracle.symbol()).to.equal("RD / USD");
    });

    it("should set correct stablecoin basket indices", async () => {
      const indices = await rdOracle.stablecoinBasketIndices();
      expect(indices).to.have.lengthOf(3);
      // Verify indices are set correctly (they should match the order in the basket)
      expect(indices[0]).to.be.bignumber.equal(new BN(2));
      expect(indices[1]).to.be.bignumber.equal(new BN(3));
      expect(indices[2]).to.be.bignumber.equal(new BN(1));
    });
  });
});
