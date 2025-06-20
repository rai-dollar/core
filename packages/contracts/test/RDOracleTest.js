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
const USDC_WHALE = "0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341"; // Example: A known rich USDC address
const USDT_WHALE = "0xF977814e90dA44bFA03b6295A0616a897441aceC"; // Example: Binance USDT hot wallet
const DAI_WHALE = "0xD1668fB5F690C59Ab4B0CAbAd0f8C1617895052B"; // Example: A known rich DAI address
const RDT_WHALE = "0x7283edAEFED54d96aFA87d4BCeF0EB6f0F3eF6c6"; // REPLACE: An address holding a lot of your RDT token

const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3";

const anvilAccount1 = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";

const swapperAccount = anvilAccount1; // The account that will perform swaps and provide initial liquidity

contract("RDOracle", async accounts => {
  let RD, USDC, USDT, DAI;
  let vault, rdOracle, stablePoolFactory;
  let newPoolAddress, poolId;

  const provider = new ethers.providers.JsonRpcProvider();
  const ethersSigner = provider.getSigner(anvilAccount1);

  const QUOTE_PERIOD_FAST = 300; // 5 minutes
  const QUOTE_PERIOD_SLOW = 3600; // 1 hour
  const MIN_OBSERVATION_DELTA = 60; // 1 minute

  const USDCAddress = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"; // 6 decimals
  const USDTAddress = "0xdAC17F958D2ee523a2206206994597C13D831ec7"; // 6 decimals
  const DAIAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F"; // 18 decimals

  const RDTAddress = "0x01420eC851Ad4202894BEA0D48dE097dEeadc1a8"; // 18 decimals

  const balv3StablePoolFactory = "0xB9d01CA61b9C181dA1051bFDd28e1097e920AB14";
  const balv3Vault = "0xbA1333333333a1BA1108E8412f11850A5C319bA9";
  const balv3Router = "0xAE563E3f8219521950555F5962419C8919758Ea2";

  const stablecoins = [USDCAddress, USDTAddress, DAIAddress];

  const logsOn = false;

  async function setupContracts(logSetup = false) {
    const showLogs = logsOn && logSetup;
    USDC = await ERC20.at(USDCAddress);
    USDT = await ERC20.at(USDTAddress);
    DAI = await ERC20.at(DAIAddress);
    RD = await ERC20.at(RDTAddress);

    vault = await Vault.at(balv3Vault);
    router = await Router.at(balv3Router);

    stablePoolFactory = await StablePoolFactory.at(balv3StablePoolFactory);

    if (showLogs) {
      console.log("Setup Contracts");
      console.log("RD:", RD.address);
      console.log("USDC:", USDC.address);
      console.log("USDT:", USDT.address);
      console.log("DAI:", DAI.address);
      console.log("Vault:", vault.address);
      console.log("Router:", router.address);
      console.log("StablePoolFactory:", stablePoolFactory.address);
    }
  }

  async function logOracleState(oracleState) {
    console.log("Oracle State:", {
      sqrtPriceX96: oracleState.sqrtPriceX96.toString(),
      tick: oracleState.tick.toString(),
      observationIndex: oracleState.observationIndex.toString(),
      observationCardinality: oracleState.observationCardinality.toString(),
      observationCardinalityNext: oracleState.observationCardinalityNext.toString()
    });
  }

  function createTruffleTokenConfig(
    tokenAddress,
    tokenType = TokenType.STANDARD,
    rateProvider = ethers.constants.AddressZero,
    paysYieldFees = false
  ) {
    return [tokenAddress, tokenType, rateProvider, paysYieldFees];
  }

  async function setupTokenAcquisition(logSetup = false) {
    const showLogs = logsOn && logSetup;
    if (showLogs) {
      console.log("Starting token acquisition for swapperAccount:", swapperAccount);
    }

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

        if (showLogs) {
          console.log(
            `Attempting to acquire ${ethers.utils.formatUnits(
              amount,
              decimalsNumber
            )} ${name} from whale ${whale}...`
          );
        }

        // Ensure whale has ETH to pay for gas.
        // This gives the impersonated whale 1 ETH on the fork.
        await ethers.provider.send("hardhat_setBalance", [whale, "0xDE0B6B3A7640000"]);

        await ethers.provider.send("hardhat_impersonateAccount", [whale]);
        const whaleSigner = await ethers.getSigner(whale);
        const tokenFromWhale = new ethers.Contract(token.address, token.abi, whaleSigner);

        if (showLogs) {
          console.log(`Whale ${whale} impersonated for ${name}. Attempting transfer...`);
        }
        await tokenFromWhale.transfer(swapperAccount, amount);
        if (showLogs) {
          console.log(`Transfer call for ${name} completed.`);
        }

        await ethers.provider.send("hardhat_stopImpersonatingAccount", [whale]);

        const swapperBalance = await token.balanceOf(swapperAccount);
        if (showLogs) {
          console.log(
            `Acquired ${name}. Swapper ${name} balance: ${ethers.utils.formatUnits(
              swapperBalance.toString(),
              decimalsNumber
            )}`
          );
        }
      } catch (e) {
        console.error(`Failed to acquire ${name} from whale ${whale}. Error: ${e.message}`, e.stack);
        console.warn(
          `Skipping ${name} acquisition due to error. Liquidity/swap tests for this token might be affected.`
        );
      }
      if (showLogs) {
        console.log("Token acquisition phase complete.");
      }
    }
  }

  async function executeSwap({
    signer,
    newPoolAddress,
    _amountIn,
    _minAmountOut,
    tokenIn,
    tokenOut,
    tokenInDecimals,
    tokenOutDecimals
  }) {
    const swapperAccount = anvilAccount1;
    const amountIn = ethers.utils.parseUnits(_amountIn, tokenInDecimals); // Swap 10 RD
    const tokenInBalance = await tokenIn.balanceOf(anvilAccount1);

    if (tokenInBalance.lt(amountIn)) {
      console.warn(
        `Swapper account ${anvilAccount1} has ${ethers.utils.formatUnits(
          tokenInBalance,
          tokenInDecimals
        )} ${tokenIn.symbol}, needs ${_amountIn} ${
          tokenIn.symbol
        } for swap. Test may fail or be misleading if account is not funded externally.`
      );
    }

    const minAmountOut = ethers.utils.parseUnits(_minAmountOut, tokenOutDecimals); // Expect at least 1 USDC out

    const latestTimestamp = (await time.latest()).toNumber();
    const deadline = latestTimestamp + 3600; // 1 hour

    const permit2Contract = new ethers.Contract(
      PERMIT2_ADDRESS,
      [
        "function approve(address token, address spender, uint160 amount, uint48 expiration) external"
      ],
      signer
    );

    const expiration = Math.floor(Date.now() / 1000) + 86400; // 24 hours

    await permit2Contract.approve(tokenIn.address, router.address, amountIn.toString(), expiration);

    try {
      swapTx = await router.swapSingleTokenExactIn(
        newPoolAddress, // pool address
        tokenIn.address, // tokenIn
        tokenOut.address, // tokenOut
        amountIn, // exactAmountIn
        minAmountOut, // minAmountOut
        deadline, // deadline
        false, // wethIsEth
        "0x", // userData
        { from: swapperAccount }
      );
      return swapTx;
    } catch (e) {
      const tokenInAllowanceToPermit2 = await tokenIn.allowance(swapperAccount, PERMIT2_ADDRESS);
      console.error(
        `Router swap transaction failed for swapper ${swapperAccount}.\n` +
          `${tokenIn.symbol} Balance: ${ethers.utils.formatUnits(tokenInBalance, tokenInDecimals)} ${
            tokenIn.symbol
          } (need ${ethers.utils.formatUnits(amountIn, tokenInDecimals)} ${tokenIn.symbol}).\n` +
          `${tokenIn.symbol} Allowance to Permit2: ${ethers.utils.formatUnits(
            tokenInAllowanceToPermit2,
            tokenInDecimals
          )} ${tokenIn.symbol}.\n` +
          `Error: ${e.message}`,
        e.stack
      );
      throw e;
    }
  }

  async function increaseObservationCardinality(rdOracle, cardinalityNext) {
    try {
      await rdOracle.increaseObservationCardinalityNext(cardinalityNext);
    } catch (e) {
      console.error("Error increasing oracle cardinality:", e);
    }
  }

  async function createPool(logSetup = false) {
    const showLogs = logsOn && logSetup;
    if (showLogs) {
      console.log("constructor args");
      console.log("vault", vault.address);
      console.log("RD", RD.address);
      console.log("QUOTE_PERIOD_FAST", QUOTE_PERIOD_FAST);
      console.log("QUOTE_PERIOD_SLOW", QUOTE_PERIOD_SLOW);
      console.log("stablecoins", stablecoins);
      console.log("MIN_OBSERVATION_DELTA", MIN_OBSERVATION_DELTA);
    }

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

    if (showLogs) {
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

      if (showLogs) {
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
            if (showLogs) {
              console.log("New Pool Address via PoolCreated event:", newPoolAddress);
              console.log("Derived Pool ID:", poolId);
            }
            break;
          }
        }
      }

      if (!newPoolAddress) {
        if (showLogs) {
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
  }

  async function initializePool(logSetup = false) {
    const showLogs = logsOn && logSetup;
    const exactAmountsIn = [
      ethers.utils.parseUnits("32", RD_DECIMALS), // 10 RD
      ethers.utils.parseUnits("32", DAI_DECIMALS), // 10 DAI
      ethers.utils.parseUnits("32", USDC_DECIMALS), // 10 USDC
      ethers.utils.parseUnits("32", USDT_DECIMALS) // 10 USDT
    ];

    try {
      // Create Permit2 contract instance
      if (showLogs) {
        console.log("Setting ERC20 approvals to Permit2 first...");
      }

      // First, approve Permit2 to spend each token
      const maxApproval = ethers.constants.MaxUint256;
      await RD.approve(PERMIT2_ADDRESS, maxApproval, { from: swapperAccount });
      await DAI.approve(PERMIT2_ADDRESS, maxApproval, { from: swapperAccount });
      await USDC.approve(PERMIT2_ADDRESS, maxApproval, { from: swapperAccount });
      await USDT.approve(PERMIT2_ADDRESS, 0, { from: swapperAccount });
      await USDT.approve(PERMIT2_ADDRESS, maxApproval, { from: swapperAccount });

      if (showLogs) {
        console.log("ERC20 approvals to Permit2 complete. Now setting Permit2 allowances...");
      }

      const permit2Contract = new ethers.Contract(
        PERMIT2_ADDRESS,
        [
          "function approve(address token, address spender, uint160 amount, uint48 expiration) external"
        ],
        ethersSigner
      );

      if (showLogs) {
        console.log("Setting individual Permit2 allowances...");
      }

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

      if (showLogs) {
        console.log("Permit2 allowances set, now trying initialize...");
      }

      const initializePoolTx = await router.initialize(
        newPoolAddress,
        [RD.address, DAI.address, USDC.address, USDT.address],
        exactAmountsIn.map(amount => amount.toString()),
        "0",
        false,
        "0x",
        { from: swapperAccount }
      );

      if (showLogs) {
        console.log("Pool initialized successfully with individual permits!");
        console.log("Transaction hash:", initializePoolTx.tx);
      }
    } catch (e) {
      console.error("Error during pool initialization:", e);
    }
  }

  async function createOracle(logSetup = false) {
    const showLogs = logsOn && logSetup;
    try {
      rdOracle = await RDOracle.new(
        vault.address,
        RDTAddress,
        QUOTE_PERIOD_FAST,
        QUOTE_PERIOD_SLOW,
        stablecoins,
        MIN_OBSERVATION_DELTA
      );
      if (showLogs) {
        console.log("Oracle created successfully:", rdOracle.address);
      }
    } catch (e) {
      console.error("Error during oracle creation:", e);
    }
  }

  beforeEach(async () => {
    await setupContracts(true);
    await createOracle(true);
    await createPool(true);
  });

  describe("RDOracle Initialization", () => {
    it("should initialize with correct parameters", async () => {
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

    it("should revert if fast period >= slow period", async () => {
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

    it("should initialize oracle state with price of 1 RD/USD", async () => {
      // Get the initial sqrtPriceX96 value (2^96 for price of 1)
      const expectedSqrtPriceX96 = new BN("2").pow(new BN("96"));
      const oracleState = await rdOracle.oracleState();
      expect(oracleState.sqrtPriceX96).to.be.bignumber.equal(expectedSqrtPriceX96);
    });

    it("should initialize oracle with proper symbol", async () => {
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

    it("should revert if vault address is zero", async () => {
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

    it("should revert if RD token address is zero", async () => {
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

    it("should revert if stablecoins array is empty", async () => {
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

    it("should revert if stablecoins array contains a zero address", async () => {
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

  describe("RDOracle cardinality", async () => {
    it("should increase cardinality", async () => {
      const beforeState = await rdOracle.oracleState();
      expect(beforeState.observationCardinalityNext).to.be.bignumber.equal(new BN(1));
      await increaseObservationCardinality(rdOracle, 10);
      const afterState = await rdOracle.oracleState();
      expect(afterState.observationCardinalityNext).to.be.bignumber.equal(new BN(10));
    });
  });

  describe("Balancer Pool Hook Functionality (afterSwap)", async () => {
    beforeEach(async () => {
      await setupTokenAcquisition(true);
      await initializePool(true);
      await increaseObservationCardinality(rdOracle, 10);
    });

    it("should call the oracle hook onAfterSwap handler", async () => {
      try {
        const swapTx = await executeSwap({
          signer: ethersSigner,
          newPoolAddress,
          _amountIn: "11",
          _minAmountOut: "1",
          tokenIn: RD,
          tokenOut: USDC,
          tokenInDecimals: RD_DECIMALS,
          tokenOutDecimals: USDC_DECIMALS
        });
        // Get transaction receipt to see if the hook was called and check if the event is correct
        const receipt = await web3.eth.getTransactionReceipt(swapTx.tx);
        // Check if there are any events from the oracle
        const oracleEvents = receipt.logs.filter(
          log => log.address.toLowerCase() === rdOracle.address.toLowerCase()
        );
        expect(oracleEvents.length).to.be.equal(1);
        const eventTopic = oracleEvents[0].topics[0];
        expect(eventTopic).to.be.equal(
          web3.utils.sha3("OracleHookCalled(address,bool,uint32,uint32)")
        );
      } catch (e) {
        console.error("Error during swap:", e);
        throw e;
      }
    });

    it("should not record an observation if minObservationDelta is not met", async () => {
      const lastUpdateTime = await rdOracle.getLastUpdateTime();
      const minObservationDelta = await rdOracle.minObservationDelta();
      const currentBlockTime = (await time.latest()).toNumber();
      const timeSinceLastUpdate = currentBlockTime - lastUpdateTime.toNumber();
      const shouldUpdate = timeSinceLastUpdate >= minObservationDelta.toNumber();
      expect(shouldUpdate).to.be.equal(false);
      const oracleStateBefore = await rdOracle.oracleState();
      expect(oracleStateBefore.observationIndex.toNumber()).to.be.equal(0);

      try {
        await executeSwap({
          signer: ethersSigner,
          newPoolAddress,
          _amountIn: "11",
          _minAmountOut: "1",
          tokenIn: RD,
          tokenOut: USDC,
          tokenInDecimals: RD_DECIMALS,
          tokenOutDecimals: USDC_DECIMALS
        });
      } catch (e) {
        console.error("Error during swap:", e);
        throw e;
      }

      const oracleStateAfter = await rdOracle.oracleState();
      expect(oracleStateAfter.observationIndex.toNumber()).to.be.equal(0);
    });

    it("should record an observation if minObservationDelta is met", async () => {
      const lastUpdateTime = await rdOracle.getLastUpdateTime();
      const minObservationDelta = await rdOracle.minObservationDelta();
      await time.increase(minObservationDelta.toNumber() + 1);
      const currentBlockTime = (await time.latest()).toNumber();
      const timeSinceLastUpdate = currentBlockTime - lastUpdateTime.toNumber();
      const shouldUpdate = timeSinceLastUpdate >= minObservationDelta.toNumber();
      expect(shouldUpdate).to.be.equal(true);
      const oracleStateBefore = await rdOracle.oracleState();
      expect(oracleStateBefore.observationIndex.toNumber()).to.be.equal(0);
      try {
        await executeSwap({
          signer: ethersSigner,
          newPoolAddress,
          _amountIn: "11",
          _minAmountOut: "1",
          tokenIn: RD,
          tokenOut: USDC,
          tokenInDecimals: RD_DECIMALS,
          tokenOutDecimals: USDC_DECIMALS
        });
      } catch (e) {
        console.error("Error during swap:", e);
        throw e;
      }
      const oracleStateAfter = await rdOracle.oracleState();
      expect(oracleStateAfter.observationIndex.toNumber()).to.be.equal(1);
    });
  });

  // describe("Price Reading Functions", () => {
  //   const provider = new ethers.providers.JsonRpcProvider();
  //   const ethersSigner = provider.getSigner(anvilAccount1);
  //   it("should read fast price correctly", async () => {
  //     const fastPrice = await rdOracle.readFast();
  //     expect(fastPrice).to.be.bignumber.gt(new BN(0));
  //   });
  // });
});
