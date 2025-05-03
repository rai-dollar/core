pragma solidity ^0.8.24;

import {IERC20} from "./Vendor/balancer-v3/dependencies/openzeppelin/contracts/interfaces/IERC20.sol";

import {BaseHooks} from "./Vendor/balancer-v3/vault/contracts/BaseHooks.sol";

import {IHooks} from "./Vendor/balancer-v3/interfaces/contracts/vault/IHooks.sol";
import {IVault} from "./Vendor/balancer-v3/interfaces/contracts/vault/IVault.sol";
import {IAggregatorRouter} from "./Vendor/balancer-v3/interfaces/contracts/vault/IAggregatorRouter.sol";

import {AggregatorV3Interface} from "./Vendor/balancer-v3/dependencies/chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {VaultGuard} from "./Vendor/balancer-v3/vault/contracts/VaultGuard.sol";
import {HookFlags, TokenConfig, LiquidityManagement, AfterSwapParams} from "./Vendor/balancer-v3/interfaces/contracts/vault/VaultTypes.sol";

import {BasePoolFactory} from "./Vendor/balancer-v3/pool-utils/contracts/BasePoolFactory.sol";

import {IOracle} from "./Interfaces/IOracle.sol";

// Note: If > 50% of tokens in pool are yield bearing must use rate provider for token
//  https://docs.balancer.fi/partner-onboarding/onboarding-overview/rate-providers.html

contract Oracle is IOracle, BaseHooks, VaultGuard {
    // --- Registry ---
    address public pool;

    address public constant AGGREGATOR_ROUTER = 0x309abcAeFa19CA6d34f0D8ff4a4103317c138657;

    // --- Data ---
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public RD = 0x0000000000000000000000000000000000000000;

    address USDC_CL_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address USDT_CL_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address DAI_CL_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;

    constructor(IVault vault) VaultGuard(vault) {}

    /// @inheritdoc IHooks
    function onRegister(
        address _factory,
        address _pool,
        TokenConfig[] memory _tokenConfig,
        LiquidityManagement calldata _liquidityManagement
    ) public override onlyVault returns (bool) {
        if (pool != address(0)) {
            revert Oracle_AlreadyRegistered();
        }
        pool = _pool;

        // Check if pool was created by the allowed factory.
        if (!BasePoolFactory(_factory).isPoolFromFactory(_pool)) {
            revert Oracle_PoolNotFromFactory(_pool);
        }
        return true;
    }

    /// @inheritdoc IHooks
    function getHookFlags() public pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        return hookFlags;
    }

    function onAfterSwap(
        AfterSwapParams calldata params_
    ) public override onlyVault returns (bool, uint256) {
        // If time since last observation > minDelta then update price in observations
        _updatePrice();
        return (true, 0);
    }

    // Get's RD price and saves it to the observations
    function _updatePrice() internal {
        // TODO: Implement price update
    }

    // Get RD price
    function _getPrice() internal returns (uint256) {
        // 1. Get price of RD in terms of each other token in the pool (# of base units of USDC received for 1 base unit of RD)
        // This is the balancer v3 router
        IAggregatorRouter aggregatorRouter = IAggregatorRouter(AGGREGATOR_ROUTER);

        // Get price of RD in terms of USDC
        uint256 amountOut_USDC_base = aggregatorRouter.querySwapSingleTokenExactIn(
            pool, // Address of the liquidity pool
            IERC20(RD), // Token to be swapped from
            IERC20(USDC), // Token to be swapped to
            1, // Exact amounts of input tokens to send
            address(this), //  The sender passed to the operation
            bytes("") // Additional data to pass to the operation
        );

        // Get price of RD in terms of USDT
        uint256 amountOut_USDT_base = aggregatorRouter.querySwapSingleTokenExactIn(
            pool,
            IERC20(RD),
            IERC20(USDT),
            1,
            address(this),
            bytes("")
        );

        // Get price of RD in terms of DAI
        uint256 amountOut_DAI_base = aggregatorRouter.querySwapSingleTokenExactIn(
            pool,
            IERC20(RD),
            IERC20(DAI),
            1,
            address(this),
            bytes("")
        );

        uint256 RD_DECIMALS = 18;
        uint256 INTERNAL_PRECISION = 1e18;

        // 2. Get CL price of each other token in the pool

        // Get USDC Chainlink price
        (, int256 _USDC_feedResult, , uint256 _USDC_feedTimestamp, ) = AggregatorV3Interface(
            USDC_CL_FEED
        ).latestRoundData();

        // Get USDT Chainlink price
        (, int256 _USDT_feedResult, , uint256 _USDT_feedTimestamp, ) = AggregatorV3Interface(
            USDT_CL_FEED
        ).latestRoundData();

        // Get DAI Chainlink price
        (, int256 _DAI_feedResult, , uint256 _DAI_feedTimestamp, ) = AggregatorV3Interface(
            DAI_CL_FEED
        ).latestRoundData();

        // 3. Calculate USD price of RD in terms of each other token in the pool

        uint256 num_usdc = amountOut_USDC_base *
            uint256(_USDC_feedResult) *
            (10 ** RD_DECIMALS) *
            INTERNAL_PRECISION;
        uint256 den_usdc = uint256(10 ** 8) * uint256(10 ** USDC_DECIMALS);
        uint256 priceRD_via_USDC_scaled = (den_usdc == 0) ? 0 : num_usdc / den_usdc;

        uint256 num_usdt = amountOut_USDT_base *
            uint256(_USDT_feedResult) *
            (10 ** RD_DECIMALS) *
            INTERNAL_PRECISION;
        uint256 den_usdt = uint256(10 ** 8) * uint256(10 ** USDT_DECIMALS);
        uint256 priceRD_via_USDT_scaled = (den_usdt == 0) ? 0 : num_usdt / den_usdt;

        uint256 num_dai = amountOut_DAI_base *
            uint256(_DAI_feedResult) *
            (10 ** RD_DECIMALS) *
            INTERNAL_PRECISION;
        uint256 den_dai = uint256(10 ** 8) * uint256(10 ** DAI_DECIMALS);
        uint256 priceRD_via_DAI_scaled = (den_dai == 0) ? 0 : num_dai / den_dai;

        // 4. Calculate final RD price in USD

        uint256 final_RD_Price_Scaled = (priceRD_via_USDC_scaled +
            priceRD_via_USDT_scaled +
            priceRD_via_DAI_scaled) / 3;
    }
}
