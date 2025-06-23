// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {PriceFeedBase} from "./PriceFeedBase.sol";
import {LiquityMath} from "./Common/LiquityMath.sol";
import {Constants as C} from "./Common/Constants.sol";

/**
* this contract is used to fetch the price of a token from a composite of two oracles
* the primary/fallback oracle is used to fetch the price of the token in ETH
* the ethUsdOracle is used to fetch the price of ETH in USD
* the price of the token in USD is then calculated by multiplying the price of the token in ETH by the price of ETH in USD
* if the price of the token in ETH is not available, the price of the token in USD is fetched from the rate provider
* if the price of ETH in USD is not available, the price of the token in USD is fetched from the first oracle
* if both oracles are not available, the price of the token in USD is fetched from the rate provider
 */
abstract contract CompositePriceFeedBase is PriceFeedBase {
    address public ethUsdOracle;
    address public rateProvider;

    constructor(address _primaryOracle, address _fallbackOracle, address _token, address _rateProvider, address _ethUsdOracle) PriceFeedBase(_primaryOracle, _fallbackOracle, _token) {
        rateProvider = _rateProvider;
        ethUsdOracle = _ethUsdOracle;
    }

    event EthUsdPriceFailed(address ethUsdOracle);
    event CanonicalRateFailed(address rateProvider);

    // --- Internal Functions ---

    //if oracle providers are in shutdown, fetch the price from the specified rate provider
    function _fetchPriceEthUsdxLstRate() internal view returns (Response memory response){
        Response memory canonicalRateResponse = _fetchCanonicalRate();
        if (!canonicalRateResponse.success) {
            emit CanonicalRateFailed(rateProvider);
            return lastGoodResponse;
        }

        Response memory ethUsdPriceResponse = _fetchEthUsdPrice();
        if (!ethUsdPriceResponse.success) {
            emit EthUsdPriceFailed(ethUsdOracle);
            return lastGoodResponse;
        }
        
        // Calculate the canonical LST-USD price: USD_per_LST = USD_per_ETH * underlying_per_LST
        response.price = ethUsdPriceResponse.price * canonicalRateResponse.price / 1e18;
        response.lastUpdated = block.timestamp;
        response.success = response.price != 0 && response.lastUpdated != 0;

        return response;
    }
    
        // deviation threshold is per collateral type
    function _withinDeviationThreshold(uint256 _marketPrice, uint256 _canonicalPrice)
        internal
        pure
        returns (bool)
    {
        // Calculate the price deviation of the oracle market price relative to the canonical price
        uint256 max = _marketPrice * (C.DECIMAL_PRECISION + _deviationThreshold()) / 1e18;
        uint256 min = _canonicalPrice * (C.DECIMAL_PRECISION - _deviationThreshold()) / 1e18;

        return _marketPrice >= min && _marketPrice <= max;
    }

    // --- Overrides ---

    /// @notice must override with library of the selected oracle provider
    //override with library that fetches eth/usd from the selected oracle
    function _fetchEthUsdPrice() internal view returns (Response);

    // Returns the LST exchange rate and a bool indicating whether the exchange rate failed to return a valid rate.
    // Implementation depends on the specific LST.
    function _fetchCanonicalRate() internal view returns (Response);

    // must override with the deviation threshold for the collateral type Found in Constants.sol
    function _deviationThreshold() internal pure virtual returns (uint256);
}