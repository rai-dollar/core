const { expect } = require("chai");
const { BN, expectEvent, time } = require("@openzeppelin/test-helpers");
const { ethers } = require("hardhat");
const { Decimal } = require("decimal.js");
const _BN = require("bn.js");

const testHelpers = require("../utils/testHelpers.js");

const th = testHelpers.TestHelper;
const assertRevert = th.assertRevert;

const RDOracle = artifacts.require("./RDOracle.sol");
const Vault = artifacts.require("./Vendor/@balancer-labs/v3-vault/contracts/Vault.sol");
const StablePoolFactory = artifacts.require(
  "./Vendor/@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol"
);
const StablePool = artifacts.require(
  "./Vendor/@balancer-labs/v3-pool-stable/contracts/StablePool.sol"
);
const Router = artifacts.require("./Vendor/@balancer-labs/v3-vault/contracts/Router.sol");

const ERC20 = artifacts.require("@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20");

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const DEFAULT_AMP_FACTOR = 1000;
const BASE_MIN_SWAP_FEE = 1e12; // 0.001% (in WAD)

const TokenType = {
  STANDARD: 0,
  WITH_RATE: 1
};

const USDC_DECIMALS = 6;
const USDT_DECIMALS = 6;
const DAI_DECIMALS = 18;
const RD_DECIMALS = 18;

// Placeholder Whale Addresses - REPLACE THESE WITH ACTUAL WHALE ADDRESSES FROM MAINNET
const USDC_WHALE = "0x0AEf3ff4a9B09347A5612C1118Fd33DDAdA7ACd0"; // Example: A known rich USDC address
const USDT_WHALE = "0xF977814e90dA44bFA03b6295A0616a897441aceC"; // Example: Binance USDT hot wallet
const DAI_WHALE = "0xD1668fB5F690C59Ab4B0CAbAd0f8C1617895052B"; // Example: A known rich DAI address
const RDT_WHALE = "0x7283edAEFED54d96aFA87d4BCeF0EB6f0F3eF6c6"; // REPLACE: An address holding a lot of your RDT token

const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3";

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
  let RD, USDC, USDT, DAI, stablecoins;
  let vault, rdOracle, stablePoolFactory;
  let newPoolAddress, poolId, stablePool;

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
  const balv3Router = "0xAE563E3f8219521950555F5962419C8919758Ea2";

  const logPool = true;

  beforeEach(async () => {
    USDC = await ERC20.at(USDCAddress);
    USDT = await ERC20.at(USDTAddress);
    DAI = await ERC20.at(DAIAddress);
    RD = await ERC20.at(RDTAddress);

    stablecoins = [USDC.address, USDT.address, DAI.address];

    vault = await Vault.at(balv3Vault);

    router = await Router.at(balv3Router);

    console.log("constructor args");
    console.log("vault", vault.address);
    console.log("RD", RD.address);
    console.log("QUOTE_PERIOD_FAST", QUOTE_PERIOD_FAST);
    console.log("QUOTE_PERIOD_SLOW", QUOTE_PERIOD_SLOW);
    console.log("stablecoins", stablecoins);
    console.log("MIN_OBSERVATION_DELTA", MIN_OBSERVATION_DELTA);

    rdOracle = await RDOracle.new(
      vault.address,
      RD.address,
      QUOTE_PERIOD_FAST,
      QUOTE_PERIOD_SLOW,
      stablecoins,
      MIN_OBSERVATION_DELTA
    );

    console.log("--------------------------------");
    console.log("--------------------------------");
    console.log("rdOracle", rdOracle.address);
    console.log("--------------------------------");
    console.log("--------------------------------");

    stablePoolFactory = await StablePoolFactory.at(balv3StablePoolFactory);

    const poolName = "RD-USDC-USDT-DAI";
    const poolSymbol = "RD-USDC-USDT-DAI";

    const truffleTokenConfigs = [
      createTruffleTokenConfig(RDTAddress, TokenType.STANDARD),
      createTruffleTokenConfig(DAIAddress, TokenType.STANDARD),
      createTruffleTokenConfig(USDCAddress, TokenType.STANDARD),
      createTruffleTokenConfig(USDTAddress, TokenType.STANDARD)
    ];

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

      // Reset for each test run in case a previous run failed to find them
      newPoolAddress = null;
      poolId = null;

      if (txResponse.logs) {
        for (const log of txResponse.logs) {
          if (log.event === "PoolCreated" && log.args && log.args.pool) {
            newPoolAddress = log.args.pool;
            // Calculate poolId: Balancer V3 poolId is often the pool address itself, cast to bytes32.
            poolId = ethers.utils.hexZeroPad(newPoolAddress, 32);

            stablePool = await StablePool.at(newPoolAddress);
            // console.log("stablePool", stablePool);
            console.log("poolId", poolId);
            console.log("newPoolAddress", newPoolAddress);
            if (logPool) {
              console.log("New Pool Address via PoolCreated event:", newPoolAddress);
              console.log("Derived Pool ID:", poolId);
            }
            break;
          }
        }
      }

      if (!newPoolAddress) {
        if (logPool) {
          console.log(
            "PoolCreated event not found or pool address missing in logs. Check contract events."
          );
        }
        // Throw an error if pool isn't created, as tests below depend on it
        throw new Error("Failed to create and identify the new Balancer pool in beforeEach.");
      }
    } catch (error) {
      console.error("Error in beforeEach during pool creation:", error);
      throw error; // Re-throw to fail the test setup if pool creation fails
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
      await assertRevert(
        RDOracle.new(
          vault.address,
          RDTAddress,
          QUOTE_PERIOD_SLOW, // Using slow period as fast period
          QUOTE_PERIOD_SLOW,
          stablecoins,
          MIN_OBSERVATION_DELTA
        ),
        "Oracle_PeriodMismatch()"
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
        "Oracle_PeriodMismatch()"
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

    xit("should set correct stablecoin basket indices", async () => {
      const indices = await rdOracle.stablecoinBasketIndices();
      expect(indices).to.have.lengthOf(3);
      // Verify indices are set correctly (they should match the order in the basket)
      expect(indices[0]).to.be.bignumber.equal(new BN(2));
      expect(indices[1]).to.be.bignumber.equal(new BN(3));
      expect(indices[2]).to.be.bignumber.equal(new BN(1));
    });

    xit("should revert if vault address is zero", async () => {
      await assertRevert(
        RDOracle.new(
          ZERO_ADDRESS,
          RD.address,
          QUOTE_PERIOD_FAST,
          QUOTE_PERIOD_SLOW,
          stablecoins,
          MIN_OBSERVATION_DELTA
        ),
        "Oracle_VaultNotSet()"
      );
    });

    xit("should revert if RD token address is zero", async () => {
      await assertRevert(
        RDOracle.new(
          vault.address,
          ZERO_ADDRESS,
          QUOTE_PERIOD_FAST,
          QUOTE_PERIOD_SLOW,
          stablecoins,
          MIN_OBSERVATION_DELTA
        ),
        "Oracle_RDTokenNotSet()"
      );
    });

    xit("should revert if stablecoins array is empty", async () => {
      await assertRevert(
        RDOracle.new(
          vault.address,
          RD.address,
          QUOTE_PERIOD_FAST,
          QUOTE_PERIOD_SLOW,
          [], // Empty stablecoins array
          MIN_OBSERVATION_DELTA
        ),
        "Oracle_StablecoinBasketEmpty()"
      );
    });

    xit("should revert if stablecoins array contains a zero address", async () => {
      const stablecoinsWithZero = [USDC.address, ZERO_ADDRESS, DAI.address];
      await assertRevert(
        RDOracle.new(
          vault.address,
          RD.address,
          QUOTE_PERIOD_FAST,
          QUOTE_PERIOD_SLOW,
          stablecoinsWithZero,
          MIN_OBSERVATION_DELTA
        ),
        "Oracle_StablecoinBasketZeroAddress()"
      );
    });
  });

  describe("Balancer Pool Hook Functionality (afterSwap)", async () => {
    const provider = new ethers.providers.JsonRpcProvider();
    const ethersSigner = provider.getSigner(anvilAccount1);
    beforeEach(async () => {
      // --- Token Acquisition via Impersonation ---
      const USDC = await ERC20.at(USDCAddress);
      const USDT = await ERC20.at(USDTAddress);
      const DAI = await ERC20.at(DAIAddress);
      const RD = await ERC20.at(RDTAddress);

      const swapperAccount = anvilAccount1; // The account that will perform swaps and provide initial liquidity

      console.log("Starting token acquisition for swapperAccount:", swapperAccount);

      const tokensToAcquire = [
        {
          token: RD,
          whale: RDT_WHALE,
          amount: ethers.utils.parseUnits("10000", RD_DECIMALS),
          name: "RD"
        },
        {
          token: DAI,
          whale: DAI_WHALE,
          amount: ethers.utils.parseUnits("10000", DAI_DECIMALS),
          name: "DAI"
        },
        {
          token: USDC,
          whale: USDC_WHALE,
          amount: ethers.utils.parseUnits("10000", USDC_DECIMALS),
          name: "USDC"
        },
        {
          token: USDT,
          whale: USDT_WHALE,
          amount: ethers.utils.parseUnits("10000", USDT_DECIMALS),
          name: "USDT"
        }
      ];

      for (const { token, whale, amount, name } of tokensToAcquire) {
        try {
          const decimalsBN = await token.decimals();
          const decimalsNumber = decimalsBN.toNumber();

          console.log(
            `Attempting to acquire ${ethers.utils.formatUnits(
              amount,
              decimalsNumber
            )} ${name} from whale ${whale}...`
          );

          // Ensure whale has ETH to pay for gas.
          // This gives the impersonated whale 1 ETH on the fork.
          await ethers.provider.send("hardhat_setBalance", [whale, "0xDE0B6B3A7640000"]);

          await ethers.provider.send("hardhat_impersonateAccount", [whale]);
          const whaleSigner = await ethers.getSigner(whale);
          const tokenFromWhale = new ethers.Contract(token.address, token.abi, whaleSigner);

          console.log(`Whale ${whale} impersonated for ${name}. Attempting transfer...`);
          await tokenFromWhale.transfer(swapperAccount, amount);
          console.log(`Transfer call for ${name} completed.`);

          await ethers.provider.send("hardhat_stopImpersonatingAccount", [whale]);

          const swapperBalance = await token.balanceOf(swapperAccount);
          console.log(
            `Acquired ${name}. Swapper ${name} balance: ${ethers.utils.formatUnits(
              swapperBalance.toString(),
              decimalsNumber
            )}`
          );
        } catch (e) {
          console.error(
            `Failed to acquire ${name} from whale ${whale}. Error: ${e.message}`,
            e.stack
          );
          console.warn(
            `Skipping ${name} acquisition due to error. Liquidity/swap tests for this token might be affected.`
          );
        }
        console.log("Token acquisition phase complete.");
      }
      // --- Permit2 Approvals and Pool Initialization ---
      // const provider = new ethers.providers.JsonRpcProvider(); // Uses default RPC
      // const ethersSigner = provider.getSigner(swapperAccount);

      const exactAmountsIn = [
        ethers.utils.parseUnits("32", RD_DECIMALS), // 10 RD
        ethers.utils.parseUnits("32", DAI_DECIMALS), // 10 DAI
        ethers.utils.parseUnits("32", USDC_DECIMALS), // 10 USDC
        ethers.utils.parseUnits("32", USDT_DECIMALS) // 10 USDT
      ];

      try {
        console.log("XXXXXX");
        // Create Permit2 contract instance

        console.log("Setting ERC20 approvals to Permit2 first...");

        // First, approve Permit2 to spend each token
        const maxApproval = ethers.constants.MaxUint256;
        await RD.approve(PERMIT2_ADDRESS, maxApproval, { from: swapperAccount });
        await DAI.approve(PERMIT2_ADDRESS, maxApproval, { from: swapperAccount });
        await USDC.approve(PERMIT2_ADDRESS, maxApproval, { from: swapperAccount });
        await USDT.approve(PERMIT2_ADDRESS, 0, { from: swapperAccount });
        await USDT.approve(PERMIT2_ADDRESS, maxApproval, { from: swapperAccount });

        console.log("ERC20 approvals to Permit2 complete. Now setting Permit2 allowances...");

        const permit2Contract = new ethers.Contract(
          PERMIT2_ADDRESS,
          [
            "function approve(address token, address spender, uint160 amount, uint48 expiration) external"
          ],
          ethersSigner
        );

        console.log("Setting individual Permit2 allowances...");

        // Set individual permits
        const expiration = Math.floor(Date.now() / 1000) + 86400; // 24 hours

        await permit2Contract.approve(
          RD.address,
          router.address,
          exactAmountsIn[0].toString(),
          expiration
        );

        await permit2Contract.approve(
          DAI.address,
          router.address,
          exactAmountsIn[1].toString(),
          expiration
        );

        await permit2Contract.approve(
          USDC.address,
          router.address,
          exactAmountsIn[2].toString(),
          expiration
        );

        await permit2Contract.approve(USDT.address, router.address, "0", expiration);

        await permit2Contract.approve(
          USDT.address,
          router.address,
          exactAmountsIn[3].toString(),
          expiration
        );

        console.log("Permit2 allowances set, now trying initialize...");

        const initializePoolTx = await router.initialize(
          newPoolAddress,
          [RD.address, DAI.address, USDC.address, USDT.address],
          exactAmountsIn.map(amount => amount.toString()),
          "0",
          false,
          "0x",
          { from: swapperAccount }
        );

        console.log("Pool initialized successfully with individual permits!");
        console.log("Transaction hash:", initializePoolTx.tx);
      } catch (e) {
        console.error("Error during pool initialization:", e);
      }
    });
    xit("placeholder test", async () => {
      console.log("placeholder test");
    });

    it("should record an observation when RD is swapped for USDC via Vault", async () => {
      console.log("Starting swap test...");

      expect(poolId, "Pool ID must be set from main beforeEach. Check pool creation logs.").to.not.be
        .null;
      expect(
        newPoolAddress,
        "Pool address must be set from main beforeEach. Check pool creation logs."
      ).to.not.be.null;

      console.log("poolId for swap test", poolId);
      console.log("newPoolAddress for swap test", newPoolAddress);

      const swapperAccount = anvilAccount1;
      const amountInRD = ethers.utils.parseUnits("11", RD_DECIMALS); // Swap 10 RD

      // Check swapper has sufficient RD balance
      const rdBalance = await RD.balanceOf(swapperAccount);
      if (rdBalance.lt(amountInRD)) {
        console.warn(
          `Swapper account ${swapperAccount} has ${ethers.utils.formatUnits(
            rdBalance,
            RD_DECIMALS
          )} RD, needs 1 RD for swap. Test may fail or be misleading if account is not funded externally.`
        );
      }
      const oracleStateBefore = await rdOracle.oracleState();

      const minAmountOut = ethers.utils.parseUnits("1", USDC_DECIMALS); // Expect at least 1 USDC out
      const latestTimestamp = (await time.latest()).toNumber();
      const deadline = latestTimestamp + 3600; // 1 hour

      const permit2Contract = new ethers.Contract(
        PERMIT2_ADDRESS,
        [
          "function approve(address token, address spender, uint160 amount, uint48 expiration) external"
        ],
        ethersSigner
      );

      const expiration = Math.floor(Date.now() / 1000) + 86400; // 24 hours

      // Set Permit2 allowance for RD swap
      await permit2Contract.approve(RD.address, router.address, amountInRD.toString(), expiration);

      let swapTx;
      try {
        swapTx = await router.swapSingleTokenExactIn(
          newPoolAddress, // pool address
          RD.address, // tokenIn
          USDC.address, // tokenOut
          amountInRD, // exactAmountIn
          minAmountOut, // minAmountOut
          deadline, // deadline
          false, // wethIsEth
          "0x", // userData
          { from: swapperAccount }
        );
        console.log("swapTx", swapTx);
      } catch (e) {
        const rdAllowanceToPermit2 = await RD.allowance(swapperAccount, PERMIT2_ADDRESS);
        console.error(
          `Router swap transaction failed for swapper ${swapperAccount}.\n` +
            `RD Balance: ${ethers.utils.formatUnits(
              rdBalance,
              RD_DECIMALS
            )} RD (need ${ethers.utils.formatUnits(amountInRD, RD_DECIMALS)} RD).\n` +
            `RD Allowance to Permit2: ${ethers.utils.formatUnits(
              rdAllowanceToPermit2,
              RD_DECIMALS
            )} RD.\n` +
            `Error: ${e.message}`,
          e.stack
        );
        throw e;
      }
    });
  });
});
