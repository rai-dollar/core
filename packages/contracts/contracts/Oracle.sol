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
import {StablePool, Rounding} from "./Vendor/balancer-v3/pool-stable/contracts/StablePool.sol";

import {FixedPoint} from "./Vendor/balancer-v3/solidity-utils/contracts/math/FixedPoint.sol";
import {IOracle} from "./Interfaces/IOracle.sol";

// Note: If > 50% of tokens in pool are yield bearing must use rate provider for token
//  https://docs.balancer.fi/partner-onboarding/onboarding-overview/rate-providers.html

contract Oracle is IOracle, BaseHooks, VaultGuard {
    using FixedPoint for uint256;

    /// @inheritdoc IOracle
    uint256 public constant WAD = 1e18;

    // --- Registry ---

    /// @inheritdoc IOracle
    address public pool;

    /// @inheritdoc IOracle
    address public vault;

    /// @inheritdoc IOracle
    address public rdToken;

    /// @inheritdoc IOracle
    address[] public stablecoinBasket;

    // --- Data ---

    /// @inheritdoc IOracle
    uint8 public rdTokenIndex;

    /// @inheritdoc IOracle
    uint8[] public stablecoinBasketIndices;

    constructor(
        IVault _vault,
        address _rdToken,
        address[] memory _stablecoinBasket
    ) VaultGuard(_vault) {
        rdToken = _rdToken;
        stablecoinBasket = _stablecoinBasket;
    }

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
        AfterSwapParams calldata _params
    ) public override onlyVault returns (bool _success, uint256 _hookAdjustedAmountCalculatedRaw) {
        // If time since last observation > minDelta then update price in observations
        bool _shouldUpdate = true;

        if (_shouldUpdate) {
            // Get last balances of all tokens in the pool
            (, , , uint256[] memory _lastBalancesWad) = IVault(vault).getPoolTokenInfo(_params.pool);
            _updateSyntheticRDPrice(_lastBalancesWad);
        }

        return (true, 0);
    }

    // Get's RD price and saves it to the observations
    function _updateSyntheticRDPrice(uint256[] memory _lastBalancesWad) internal {
        // TODO: Implement price update
        uint256 _currentSyntheticRDPriceWad = _calculateInstantaneousSyntheticRDPrice(
            _lastBalancesWad
        );
    }

    /**
     * @notice Get the instantaneous synthetic RD price
     * @param  _lastBalancesWad The last balances of the pool
     * @return _syntheticRDPriceWad The instantaneous synthetic RD price
     */
    function _calculateInstantaneousSyntheticRDPrice(
        uint256[] memory _lastBalancesWad
    ) internal view returns (uint256 _syntheticRDPriceWad) {
        StablePool _pool = StablePool(pool);
        uint256 _numBalances = _lastBalancesWad.length;
        (uint256 _ampValue, , uint256 _ampPrecision) = _pool.getAmplificationParameter();
        uint256 _poolInvariant = _pool.computeInvariant(_lastBalancesWad, Rounding.ROUND_UP);
        uint256 _ampCoefficient = (_numBalances ** _numBalances) * _ampValue;

        uint256 _balancesSum;
        for (uint256 _i = 0; _i < _numBalances; _i++) {
            _balancesSum += _lastBalancesWad[_i];
        }

        // Calculate partial derivative for RD
        uint256 _derivativeRD = _calculatePartialDerivative(
            _lastBalancesWad[rdTokenIndex],
            _ampCoefficient,
            _poolInvariant,
            _balancesSum,
            _ampPrecision
        );

        // Calculate weighted sum of stablecoin prices in RD
        uint256 _weightedSumStablePriceInRD;
        // Calculate total stablecoin balance
        uint256 _totalStableBalanceWad;

        for (uint256 _i = 0; _i < stablecoinBasket.length; _i++) {
            uint8 _stableIndex = _stablecoinBasketIndices[_i];
            uint256 _stableBalanceWad = _lastBalancesWad[_stableIndex];

            // Calculate partial derivative for this stablecoin
            uint256 _derivativeStablecoin = _calculatePartialDerivative(
                _stableBalanceWad,
                _ampCoefficient,
                _poolInvariant,
                _balancesSum,
                _ampPrecision
            );

            // Price of stablecoin _i in terms of RD = _derivativeRD / _derivativeStablecoin
            uint256 _priceStableInRD = _derivativeRD.divDown(_derivativeStablecoin);

            _weightedSumStablePriceInRD += _priceStableInRD.mulDown(_stableBalanceWad);

            _totalStableBalanceWad += _stableBalanceWad;
        }
        if (_totalStableBalanceWad == 0) {
            revert Oracle_DivisionByZero();
        }

        // Average price of the stablecoin basket unit, measured in RD
        _avgBasketPriceInRD = _weightedSumStablePriceInRD.divDown(_totalStableBalanceWad);

        if (_avgBasketPriceInRD == 0) {
            revert Oracle_DivisionByZero();
        }

        // Synthetic Price RD/USD = 1 / avgBasketPriceInRD
        // Use WAD * WAD / x for 1/x equivalent, preserves WAD scaling
        _syntheticRDPriceWad = WAD.mulDown(WAD).divDown(_avgBasketPriceInRD);

        // Average price of the stablecoin basket unit, measured in RD
        uint256 _avgBasketPriceInRD = _weightedSumStablePriceInRD.divDown(_totalStableBalanceWad);
    }

    /**
     * @notice Calculate the partial derivative of the stable pool invariant for a given token
     * @dev    See Balancer v3 Stable Math Resources:
     *
     *         - https://docs.balancer.fi/concepts/explore-available-balancer-pools/stable-pool/stable-math.html#overview
     *         - https://github.com/georgeroman/balancer-v2-pools/blob/main/src/pools/stable/math.ts#L16
     *         - https://berkeley-defi.github.io/assets/material/StableSwap.pdf
     *
     * @dev
     *
     *         D = invariant (a measure of the total value in the pool)
     *         A = amplification coefficient
     *         S = sum of all token balances (x_1 + x_2 + ... + x_n)
     *         P = product of all token balances (x_1 * x_2 * ... * x_n)
     *         n = number of tokens
     *
     *         The StableSwap invariant equation is:
     *
     *         A * n^n * S + D = A * n^n * D + D^(n+1) / (n^n * P)
     *
     *         The derivative formula is:
     *
     *           df                  D^(n+1)                 1
     *         ------ = n^n * A + ------------- = n^n * A + --- * (n^n * A * S + D - n^n * A * D)
     *           dx                n^n * x * P               x
     *
     *         From the StableSwap invariant equation we isolate D^(n+1) / (n^n * P) by moving A * n^n * D to the left
     *         side of the equation, which gives us the following identity:
     *
     *         D^(n+1) / (n^n * P) = A * n^n * S + D - A * n^n * D
     *
     *         We can then rewrite the second term of the derivative formula as:
     *
     *         [ D^(n+1) / (n^n * P) ] * (1/x)
     *
     *         We then substitute the previously derived identity into the second term of the derivative formula:
     *
     *         df/dx = n^n * A + [ A * n^n * S + D - A * n^n * D ] * (1/x)
     *
     *         df/dx = n^n * A + (A * n^n * S + D - A * n^n * D) / x
     *
     *
     * @param  _tokenBalance The balance of the token
     * @param  _ampCoefficient The amplification coefficient (n^n * A)
     * @param  _poolInvariant The pool invariant (D)
     * @param  _balancesSum The sum of the balances of the pool (S)
     * @param  _ampPrecision The precision of the amplification coefficient
     * @return _partialDerivative The partial derivative for the token
     */
    function _calculatePartialDerivative(
        uint256 _tokenBalance,
        uint256 _ampCoefficient,
        uint256 _poolInvariant,
        uint256 _balancesSum,
        uint256 _ampPrecision
    ) internal pure returns (uint256 _partialDerivative) {
        if (_balancesSum == 0) {
            revert Oracle_DivisionByZero();
        }

        // The amplification parameter A is a dimensionless number that controls how
        // closely the pool's behavior mimics a constant-sum invariant (like x+y=k)
        // versus a constant-product invariant (like x*y=k)

        // _ampPrecision is a scaling factor that ensures the amplification coefficient
        // is represented in a fixed-point format (e.g. no decimals)

        // The amplification value stored in the contract is scaled by _ampPrecision
        // so we need to scale it down to WAD precision when calculating the partial
        // derivative
        //
        // True A value = A value in contract / _ampPrecision

        // Term 1 = n^n * A = _ampCoefficient
        // _ampCoefficient * (WAD / _ampPrecision) -> A is scaled to WAD precision
        uint256 term1 = _ampCoefficient.mulDown(WAD, _ampPrecision);

        // Term 2 Total = (A * n^n * S + D - A * n^n * D) / x
        // Term 2 Numerator = A * n^n * S + D - A * n^n * D
        // Term 2 Numerator Part 1 = A * n^n * S
        // Term 2 Numerator Part 2 = D
        // Term 2 Numerator Part 3 = A * n^n * D

        uint256 term2NumPart1 = _ampCoefficient.mulDown(_balancesSum, _ampPrecision);
        uint256 term2NumPart2 = _poolInvariant;
        uint256 term2NumPart3 = _ampCoefficient.mulDown(_poolInvariant, _ampPrecision);

        uint256 term2Numerator = term2NumPart1 + term2NumPart2 - term2NumPart3;

        // Term 2 = term2Numerator / _tokenBalance
        uint256 term2 = term2Numerator.divDown(_tokenBalance);

        return term1 + term2;
    }
}
