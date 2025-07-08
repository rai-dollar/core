// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {PriceFeedBase} from "./PriceFeedBase.sol";
import {LiquityMath} from "./Common/LiquityMath.sol";
import {Constants as C} from "./Common/Constants.sol";

// The CompositePriceFeed is used for feeds that incorporate both a market price oracle (e.g. STETH-USD, or RETH-ETH)
// and an LST canonical rate (e.g. WSTETH:STETH, or RETH:ETH).
// Possible states:
// market oracle: primary or fallback
// underlying asset price (eth/usd): primary or fallback
// if priceSource = lastGoodResponse on any oracle, This means the primary and fallback have failed and this asset is in shut down.
// market primary && underlying primary => Good rate
// market primary && underlying fallback => Good rate
// market fallback && underlying primary => Good rate
// market fallback && underlying fallback => Good rate
// market || underlying => lastGoodResponse => SHUTDOWN
// Rate provider is either GOOD or Oracle is SHUT DOWN for composite feeds
abstract contract CompositePriceFeedBase is PriceFeedBase {
    Oracle public primaryCompositeOracle;
    Oracle public fallbackCompositeOracle;
    
    address public rateProvider;

    // Determines where the PriceFeed sources data from. Possible states:
    // - primary: Uses the primary price calcuation, which depends on the specific feed
    // - fallback: Uses using the fallback oracle in case of primary oracle failure
    // - lastGoodPrice: the price feed is shut down and will only return the last good price recorded
    PriceSource public compositePriceSource;

    uint256 public compositeStalenessThreshold;

    event CompositePriceSourceChanged(PriceSource compositePriceSource, uint256 timestamp);

    constructor(
        OracleConfig memory _marketOracleConfig,
        OracleConfig memory _ethUsdOracleConfig,
        address _token, 
        address _rateProvider,
        uint256 _deviationThreshold
        ) PriceFeedBase(_marketOracleConfig, _token, _deviationThreshold) {
            rateProvider = _rateProvider;

            primaryCompositeOracle.oracle = _ethUsdOracleConfig.primaryOracle;
            primaryCompositeOracle.stalenessThreshold = _ethUsdOracleConfig.primaryStalenessThreshold;
            fallbackCompositeOracle.oracle = _ethUsdOracleConfig.fallbackOracle;
            fallbackCompositeOracle.stalenessThreshold = _ethUsdOracleConfig.fallbackStalenessThreshold;

            compositePriceSource = PriceSource.primaryOracle;
        }
    

    // --- Overrides ---
    
    /// @notice must override with library of the selected oracle provider
    //override with library that fetches eth/usd from the selected oracle
    function _fetchPrimaryCompositeOraclePrice() internal virtual view returns (Response memory);

    //override with library that fetches eth/usd from the fallback oracle
    function _fetchFallbackCompositeOraclePrice() internal virtual view returns (Response memory);

    // Returns the LST exchange rate and a bool indicating whether the exchange rate failed to return a valid rate.
    // Implementation depends on the specific priceSource
    function _fetchCanonicalRate() internal virtual view returns (Response memory);


    // --- Internal Functions ---

    // use this function to get the response from the primary oracle and check if it is good to return correct success bool
    function _getPrimaryCompositeOracleResponse() internal returns (Response memory) {
        Response memory response = _fetchPrimaryCompositeOraclePrice();
        response.success = isGoodResponse(response, primaryCompositeOracle.stalenessThreshold);
        return response;
    }

    // use this function to get the response from the fallback oracle and check if it is good to return correct success bool
    function _getFallbackCompositeOracleResponse() internal returns (Response memory) {
        Response memory response = _fetchFallbackCompositeOraclePrice();
        response.success = isGoodResponse(response, fallbackCompositeOracle.stalenessThreshold);
        return response;
    }

    function _compositePrimaryIsSet() internal view returns (bool) {
        return primaryCompositeOracle.oracle != address(0) && primaryCompositeOracle.stalenessThreshold > 0;
    }

    function _compositeFallbackIsSet() internal view returns (bool) {
        return fallbackCompositeOracle.oracle != address(0) && fallbackCompositeOracle.stalenessThreshold > 0;
    }

    // if composite oracle is in shutdown state
    function _setCompositePriceSource(PriceSource _priceSource) internal virtual {
        if (compositePriceSource != _priceSource) {
            compositePriceSource = _priceSource;
            emit CompositePriceSourceChanged(compositePriceSource, block.timestamp);
        }
    }

    // @note must override in child contract to handle full shutdown logic
    function _shutdownAndSwitchToLastGoodResponse(FailureType _failureType) internal virtual override {
        // set market and composite price source to last good response
        lastGoodResponse.success = false;
        _setMarketPriceSource(PriceSource.lastGoodResponse);
        _setCompositePriceSource(PriceSource.lastGoodResponse); 

        emit ShutdownInitiated(_failureType, block.timestamp);
    }

    function _getMaxRedemptionPrice(Response memory _stEthUsdPriceResponse, 
    Response memory _ethUsdPriceResponse, 
    Response memory _lstRateResponse
    ) internal view returns (uint256 _redemptionPrice) {
        uint256 maxPrice =  LiquityMath._max(_stEthUsdPriceResponse.price, _ethUsdPriceResponse.price);

        return _getPrice(maxPrice, _lstRateResponse.price);
    }

    function _getPrice(uint256 _maxPrice, 
    uint256 _lstRate
    ) internal pure returns (uint256 _redemptionPrice) {
        _redemptionPrice =  _maxPrice * _lstRate / 1e18;
    }

}