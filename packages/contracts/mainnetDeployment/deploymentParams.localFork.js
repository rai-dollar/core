const externalAddrs  = {
  // https://data.chain.link/eth-usd
  CHAINLINK_ETHUSD_PROXY: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
  CHAINLINK_STETHUSD_PROXY: "0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8",
  CHAINLINK_STETHETH_PROXY: "0x86392dC19c0b719886221c78AB11eb8Cf5c52812",
  CHAINLINK_STETHPERWSTETH_PROXY: "0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714",
  CHAINLINK_WBTCBTC_PROXY: "0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23",
  CHAINLINK_BTCETH_PROXY: "0xdeb288F737066589598e9214E782fa5A8eD689e8",
  CHAINLINK_BTCUSD_PROXY: "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
  CHAINLINK_RSETHETH_PROXY: "0x9d2F2f96B24C444ee32E57c04F7d944bcb8c8549",
  // https://docs.tellor.io/tellor/integration/reference-page
  TELLOR_MASTER:"0x88dF592F8eb5D7Bd38bFeF7dEb0fBc02cf3778a0",
  // https://uniswap.org/docs/v2/smart-contracts/factory/
  UNISWAP_V2_FACTORY: "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",
  UNISWAP_V2_ROUTER02: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
  // https://etherscan.io/token/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2
  WETH_ERC20: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
  RETH_ERC20: "0xae78736Cd615f374D3085123A210448E74Fc6393",
  WBTC_ERC20: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
  STETH_ERC20: "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84",
  WSTETH_ERC20: "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
}

const priceFeedParams = {
  ethUsdStalenessThreshold: 86400, // 24 hours
  stEthUsdStalenessThreshold: 86400, // 24 hours
  rethUsdStalenessThreshold: 86400, // 24 hours
  wbtcBtcStalenessThreshold: 86400, // 24 hours
  btcUsdStalenessThreshold: 86400, // 24 hours
  btcEthStalenessThreshold: 86400, // 24 hours
  rsEthEthStalenessThreshold: 172800, // 48 hours
}

const liquityAddrs = {
  GENERAL_SAFE:"0x8be7e24263c199ebfcfd6aebca83f8d7ed85a5dd",  // Hardhat dev address
  LQTY_SAFE:"0x20c81d658aae3a8580d990e441a9ef2c9809be74",  //  Hardhat dev address
  DEPLOYER: "0x31c57298578f7508B5982062cfEc5ec8BD346247" // hardhat first account
}

const beneficiaries = {
  TEST_INVESTOR_A: "0xdad05aa3bd5a4904eb2a9482757be5da8d554b3d",
  TEST_INVESTOR_B: "0x625b473f33b37058bf8b9d4c3d3f9ab5b896996a",
  TEST_INVESTOR_C: "0x9ea530178b9660d0fae34a41a02ec949e209142e",
  TEST_INVESTOR_D: "0xffbb4f4b113b05597298b9d8a7d79e6629e726e8",
  TEST_INVESTOR_E: "0x89ff871dbcd0a456fe92db98d190c38bc10d1cc1"
}

const OUTPUT_FILE = './mainnetDeployment/localForkDeploymentOutput.json'

const waitFunction = async () => {
  // Fast forward time 1000s (local mainnet fork only)
  ethers.provider.send("evm_increaseTime", [1000])
  ethers.provider.send("evm_mine") 
}

const GAS_PRICE = 1000
const TX_CONFIRMATIONS = 1 // for local fork test

module.exports = {
  externalAddrs,
  liquityAddrs,
  beneficiaries,
  OUTPUT_FILE,
  waitFunction,
  GAS_PRICE,
  TX_CONFIRMATIONS,
};
