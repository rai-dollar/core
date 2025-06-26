// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {PriceFeedBase} from "./PriceFeedBase.sol";
import {LiquityMath} from "./Common/LiquityMath.sol";
import {Constants as C} from "./Common/Constants.sol";


abstract contract CompositePriceFeedBase is PriceFeedBase {
    Oracle public ethUsdOracle;
    Oracle public ethUsdOracleFallback;
    
    address public rateProvider;

    //last good response from the primary or fallback eth/usd oracle
    Response public lastGoodEthUsdResponse;

    //where the eth/usd price is coming from: primaryOracle, fallbackOracle, or lastGoodResponse
    PriceSource public compositePriceSource;

    event EthUsdPriceFailed(address ethUsdOracle);
    event CanonicalRateFailed(address rateProvider);
    event LastGoodEthUsdResponse(uint256 price, uint256 lastUpdated);
    event CompositePriceSourceChanged(PriceSource compositePriceSource);

    constructor(
        OracleConfig memory _marketOracleConfig,
        OracleConfig memory _ethUsdOracleConfig,
        address _token, 
        address _rateProvider,
        uint256 _deviationThreshold
        ) PriceFeedBase(_marketOracleConfig, _token, _deviationThreshold) {
        rateProvider = _rateProvider;
        ethUsdOracle.oracle = _ethUsdOracleConfig.primaryOracle;
        ethUsdOracle.stalenessThreshold = _ethUsdOracleConfig.primaryStalenessThreshold;
        ethUsdOracleFallback.oracle = _ethUsdOracleConfig.fallbackOracle;
        ethUsdOracleFallback.stalenessThreshold = _ethUsdOracleConfig.fallbackStalenessThreshold;
        compositePriceSource = PriceSource.primaryOracle;
    }
    
    // --- Internal Functions ---
        
    // gets eth/usd price from the primary or fallback oracle
    // if the price is not available, it will return the last good price
    // if the price is not available from the primary or fallback oracle, it will return the last good price

    function _fetchEthUsdPrice() internal returns (Response memory _ethUsdPriceResponse) {
        // if oracle is in shutdown state, return last good price
        if (compositePriceSource == PriceSource.lastGoodResponse) {
            return lastGoodEthUsdResponse;
        }

        if (compositePriceSource == PriceSource.primaryOracle) {
            // get primary response
            Response memory primaryEthUsdPriceResponse = _fetchPrimaryEthUsdPrice();
            bool primaryEthUsdPriceSuccess = isGoodResponse(primaryEthUsdPriceResponse, ethUsdOracle.stalenessThreshold);
    
                if (primaryEthUsdPriceSuccess) {
                _saveLastGoodEthUsdResponse(primaryEthUsdPriceResponse);
                return primaryEthUsdPriceResponse;

                } else if (!primaryEthUsdPriceSuccess && ethUsdOracleFallback.oracle != address(0)) {
                    Response memory fallbackEthUsdPriceResponse = _fetchFallbackEthUsdPrice();
                    bool fallbackEthUsdPriceSuccess = isGoodResponse(fallbackEthUsdPriceResponse, ethUsdOracleFallback.stalenessThreshold);

                        if (fallbackEthUsdPriceSuccess) {
                            _setCompositePriceSource(PriceSource.fallbackOracle);
                            _saveLastGoodEthUsdResponse(fallbackEthUsdPriceResponse);
                            return fallbackEthUsdPriceResponse;
                        } else {
                            _setCompositePriceSource(PriceSource.lastGoodResponse);
                            return lastGoodEthUsdResponse;
                        }
                } else {
                    // if the fallback oracle is not set, shutdown the price feed and revert to last good price
                    _setCompositePriceSource(PriceSource.lastGoodResponse);
                    return lastGoodEthUsdResponse;
                }
        }
        
        // if the price is not available from the primary oracle, fetch from the fallback oracle
        if (compositePriceSource == PriceSource.fallbackOracle) {

            Response memory fallbackEthUsdPriceResponse = _fetchFallbackEthUsdPrice();
            bool fallbackEthUsdPriceSuccess = isGoodResponse(fallbackEthUsdPriceResponse, ethUsdOracleFallback.stalenessThreshold);

            // get primary response
            Response memory primaryEthUsdPriceResponse = _fetchPrimaryEthUsdPrice();
            bool safeToUseCompositePrimary = isGoodResponse(primaryEthUsdPriceResponse, ethUsdOracle.stalenessThreshold) && isGoodResponse(fallbackEthUsdPriceResponse, ethUsdOracleFallback.stalenessThreshold) && _withinDeviationThreshold(primaryEthUsdPriceResponse.price, fallbackEthUsdPriceResponse.price, C.FALLBACK_PRIMARY_DEVIATION_THRESHOLD);

            // if the primary oracle is good and within the deviation threshold, set the eth/usd price source to the primary oracle
                if (safeToUseCompositePrimary) {
                    _setCompositePriceSource(PriceSource.primaryOracle);
                    _saveLastGoodEthUsdResponse(primaryEthUsdPriceResponse);
                    return primaryEthUsdPriceResponse;
                // if the primary oracle is not good, return fallback response
                } else if (fallbackEthUsdPriceSuccess && !safeToUseCompositePrimary) {
                    _saveLastGoodEthUsdResponse(fallbackEthUsdPriceResponse);
                    return fallbackEthUsdPriceResponse;
                // if both oracles are bad, shutdown the price feed and revert to last good price
                } else {
                    _setCompositePriceSource(PriceSource.lastGoodResponse);
                    return lastGoodEthUsdResponse;
                }
        }
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

    function _setCompositePriceSource(PriceSource _priceSource) internal virtual {
        if (compositePriceSource != _priceSource) {
            compositePriceSource = _priceSource;
            emit CompositePriceSourceChanged(compositePriceSource);
        }

        if (_priceSource == PriceSource.lastGoodResponse) {
            _setMarketPriceSource(PriceSource.lastGoodResponse);
            emit ShutdownInitiated("Composite Oracle Shut Down", block.number);
        }
    }

    // if composite oracle is in shutdown state, also shut down the market oracle
    function _setMarketPriceSource(PriceSource _marketPriceSource) internal virtual override {
        if (marketPriceSource != _marketPriceSource) {
            marketPriceSource = _marketPriceSource;
            emit MarketPriceSourceChanged(marketPriceSource);
        }

        if (_marketPriceSource == PriceSource.lastGoodResponse) {
            _setCompositePriceSource(PriceSource.lastGoodResponse);
            emit ShutdownInitiated("Market Oracle Shut Down", block.number);
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