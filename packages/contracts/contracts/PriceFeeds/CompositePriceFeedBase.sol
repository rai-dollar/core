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
    Oracle public ethUsdOracle;
    Oracle public ethUsdOracleFallback;
    
    address public rateProvider;

    //last good response from the primary or fallback eth/usd oracle
    Response public lastGoodEthUsdResponse;

    //where the eth/usd price is coming from: primaryOracle, fallbackOracle, or lastGoodResponse
    PriceSource public ethUsdPriceSource;

    event EthUsdPriceFailed(address ethUsdOracle);
    event CanonicalRateFailed(address rateProvider);
    event LastGoodEthUsdResponse(uint256 price, uint256 lastUpdated);
    event EthUsdPriceSourceChanged(PriceSource ethUsdPriceSource);

    constructor(
        OracleConfig memory _marketOracleConfig,
        OracleConfig memory _ethUsdOracleConfig,
        address _token, 
        address _rateProvider
        ) PriceFeedBase(_marketOracleConfig, _token) {
        rateProvider = _rateProvider;
        ethUsdOracle.oracle = _ethUsdOracleConfig.primaryOracle;
        ethUsdOracle.stalenessThreshold = _ethUsdOracleConfig.primaryStalenessThreshold;
        ethUsdOracleFallback.oracle = _ethUsdOracleConfig.fallbackOracle;
        ethUsdOracleFallback.stalenessThreshold = _ethUsdOracleConfig.fallbackStalenessThreshold;
        ethUsdPriceSource = PriceSource.primaryOracle;
    }
    
    // --- Internal Functions ---
    
    // deviation threshold is per collateral type
    function _withinDeviationThreshold(uint256 _priceToCheck, uint256 _referencePrice, uint256 _deviationThreshold)
        internal
        pure
        returns (bool)
    {
        // Calculate the price deviation of the oracle market price relative to the canonical price
        uint256 max = _referencePrice * (C.DECIMAL_PRECISION + _deviationThreshold) / 1e18;
        uint256 min = _referencePrice * (C.DECIMAL_PRECISION - _deviationThreshold) / 1e18;

        return _priceToCheck >= min && _priceToCheck <= max;
    }
    
    // gets eth/usd price from the primary or fallback oracle
    // if the price is not available, it will return the last good price
    // if the price is not available from the primary or fallback oracle, it will return the last good price

    function _fetchEthUsdPrice() internal returns (Response memory) {
        if (ethUsdPriceSource == PriceSource.lastGoodResponse) {
            return lastGoodEthUsdResponse;
        }

        Response memory primaryEthUsdPriceResponse = _fetchPrimaryEthUsdPrice();
        bool primaryEthUsdPriceSuccess = isGoodResponse(primaryEthUsdPriceResponse, ethUsdOracle.stalenessThreshold);

        if (primaryEthUsdPriceSuccess) {
            _setEthUsdPriceSource(PriceSource.primaryOracle);
            _saveLastGoodEthUsdResponse(primaryEthUsdPriceResponse);
            return primaryEthUsdPriceResponse;
        }

        Response memory fallbackEthUsdPriceResponse = _fetchFallbackEthUsdPrice();
        bool fallbackEthUsdPriceSuccess = isGoodResponse(fallbackEthUsdPriceResponse, ethUsdOracleFallback.stalenessThreshold);

        if (fallbackEthUsdPriceSuccess) {
            _setEthUsdPriceSource(PriceSource.fallbackOracle);
            _saveLastGoodEthUsdResponse(fallbackEthUsdPriceResponse);
            return fallbackEthUsdPriceResponse;
        }

        _setEthUsdPriceSource(PriceSource.lastGoodResponse);
        return lastGoodEthUsdResponse;
    }

    // --- Overrides ---

    /// @notice must override with library of the selected oracle provider
    //override with library that fetches eth/usd from the selected oracle
    function _fetchPrimaryEthUsdPrice() internal virtual view returns (Response memory);

    //override with library that fetches eth/usd from the fallback oracle
    function _fetchFallbackEthUsdPrice() internal virtual view returns (Response memory);

    // override with library that fetches the canonical rate
    // Returns the LST exchange rate and a bool indicating whether the exchange rate failed to return a valid rate.
    // Implementation depends on the specific priceSource
    function _fetchCanonicalRate() internal virtual view returns (Response memory);


    // --- Internal Functions ---

    function _saveLastGoodEthUsdResponse(Response memory _response) internal {
        if (_response.success) {
            lastGoodEthUsdResponse = _response;
            emit LastGoodEthUsdResponse(_response.price, _response.lastUpdated);
        }
    }

    function _setEthUsdPriceSource(PriceSource _priceSource) internal virtual {
        if (ethUsdPriceSource != _priceSource) {
            ethUsdPriceSource = _priceSource;
            emit EthUsdPriceSourceChanged(ethUsdPriceSource);
        }
    }

    function _getRedemptionPrice(Response memory _stEthUsdPriceResponse, 
    Response memory _ethUsdPriceResponse, 
    Response memory _stethPerWstethResponse
    ) internal view returns (Response memory _redemptionResponse) {
        _redemptionResponse.price =  LiquityMath._max(_stEthUsdPriceResponse.price, _ethUsdPriceResponse.price) * _stethPerWstethResponse.price / 1e18;

        _redemptionResponse.success = _redemptionResponse.price != 0;
        _redemptionResponse.lastUpdated = block.timestamp;

        return _redemptionResponse;
    }

}