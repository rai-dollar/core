// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {PriceFeedBase} from "./PriceFeedBase.sol";
import {LiquityMath} from "./Common/LiquityMath.sol";
import {Constants as C} from "./Common/Constants.sol";


abstract contract CompositePriceFeedBase is PriceFeedBase {
    Oracle public primaryCompositeOracle;
    Oracle public fallbackCompositeOracle;
    
    address public rateProvider;

    //last good response from the primary or fallback eth/usd oracle
    Response public lastGoodCompositeResponse;

    //where the eth/usd price is coming from: primaryOracle, fallbackOracle, or lastGoodResponse
    PriceSource public compositePriceSource;

    event CompositePriceFailed(address compositeOracle);
    event CanonicalRateFailed(address rateProvider);
    event LastGoodCompositeResponse(uint256 price, uint256 lastUpdated);
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

    function _getPrimaryCompositeOracleResponse() internal returns (Response memory) {
        Response memory response = _fetchPrimaryCompositeOraclePrice();
        response.success = isGoodResponse(response, primaryCompositeOracle.stalenessThreshold);
        return response;
    }

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

    function _storeLastGoodCompositeResponse(Response memory _response) internal {
        if (_response.success) {
            lastGoodCompositeResponse = _response;
            emit LastGoodCompositeResponse(_response.price, _response.lastUpdated);
        }
    }

    // if composite oracle is in shutdown state
    function _setCompositePriceSource(PriceSource _priceSource) internal virtual {
        if (compositePriceSource != _priceSource) {
            compositePriceSource = _priceSource;
            emit CompositePriceSourceChanged(compositePriceSource, block.timestamp);

                if (_priceSource == PriceSource.lastGoodResponse) {
                    _shutdownAndSwitchToLastGoodCompositeResponse();
                }
        }
    }

    function _shutdownAndSwitchToLastGoodCompositeResponse() internal virtual {
        // TODO:include shutdown logic here
        // set last good response to false to indicate that oracle response is not good
        lastGoodCompositeResponse.success = false;
        emit ShutdownInitiated("Composite Oracle Failure", block.timestamp);
    }

    function _getMaxRedemptionPrice(Response memory _stEthUsdPriceResponse, 
    Response memory _ethUsdPriceResponse, 
    Response memory _lstRateResponse
    ) internal view returns (Response memory _redemptionResponse) {
        uint256 maxPrice =  LiquityMath._max(_stEthUsdPriceResponse.price, _ethUsdPriceResponse.price);
        
        _redemptionResponse.price = _getRedemptionPrice(maxPrice, _lstRateResponse.price);
        _redemptionResponse.success = _redemptionResponse.price != 0;
        _redemptionResponse.lastUpdated = block.timestamp;

        return _redemptionResponse;
    }

    function _getRedemptionPrice(uint256 _maxPrice, 
    uint256 _lstRate
    ) internal pure returns (uint256 _redemptionPrice) {
        _redemptionPrice =  _maxPrice * _lstRate / 1e18;
    }

}