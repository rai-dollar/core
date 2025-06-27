// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IPriceFeed} from "./Interfaces/IPriceFeed.sol";
import {LiquityMath} from "./Common/LiquityMath.sol";
import {IERC20} from "./Interfaces/IERC20.sol";
import {Constants as C} from "./Common/Constants.sol";
import "hardhat/console.sol";

abstract contract PriceFeedBase is IPriceFeed {
    using LiquityMath for uint256;
    
    // this should be the token / usd oracle
    Oracle public primaryOracle;
    // this is the fallback in case the primary oracle fails
    Oracle public fallbackOracle;
    // this is the base token for which the price is being fetched
    IERC20 public token;

    uint256 public deviationThreshold;

    // The last good price returned by any oracle
    uint256 public lastGoodMarketPrice;
    
    // Where the price feed is getting its price: primaryOracle, fallbackOracle, or shutdown
    PriceSource public marketPriceSource;
    
    event MarketPriceSourceChanged(PriceSource marketPriceSource);
    event LastGoodMarketPriceUpdated(uint256 price, uint256 lastUpdated);
    event ShutdownInitiated(string reason, uint256 blockNumber);
    
    constructor(OracleConfig memory _marketOracleConfig, address _token, uint256 _deviationThreshold) {
        primaryOracle.oracle = _marketOracleConfig.primaryOracle;
        primaryOracle.stalenessThreshold = _marketOracleConfig.primaryStalenessThreshold;

        fallbackOracle.oracle = _marketOracleConfig.fallbackOracle;
        fallbackOracle.stalenessThreshold = _marketOracleConfig.fallbackStalenessThreshold;

        token = IERC20(_token);
        assert(token.decimals() != 0);
        marketPriceSource = PriceSource.primaryOracle;
        deviationThreshold = _deviationThreshold;
    }

    // --- Functions ---

    // must override with specific logic for each collateral type and oracle combination
    function fetchPrice(bool _isRedemption) external virtual returns (uint256);

    /// @notice fetches the price from the primary or fallback oracle
    /// @dev if the primary oracle is good, it will return the price from the primary oracle
    /// @dev if the primary oracle is bad, it will return the price from the fallback oracle
    /// @dev if both oracles are bad, it will return the last good price and enter a shutdown state
    function _fetchMarketOraclePrice() internal returns (uint256, bool){
        // if the price feed is in a shutdown state, return the last good price
        if (marketPriceSource == PriceSource.lastGoodPrice) {
            return (lastGoodMarketPrice, true);
        }

        // if the price feed is using the primary oracle
        if(marketPriceSource == PriceSource.primaryOracle) {
                // get primary response
            Response memory primaryResponse = _fetchPriceFromPrimaryOracle();
            bool isGoodPrimaryResponse = isGoodResponse(primaryResponse, primaryOracle.stalenessThreshold);
            
                if (isGoodPrimaryResponse) {
                    _setMarketPriceSource(PriceSource.primaryOracle);
                    _storeResponse(primaryResponse);
                    
                    return (primaryResponse.price, primaryResponse.success);
                } else if (!isGoodPrimaryResponse && fallbackOracle.oracle != address(0)) {
                // if primary is not good, get fallback response
                Response memory fallbackResponse = _fetchPriceFromFallbackOracle();
                bool isGoodFallbackResponse = isGoodResponse(fallbackResponse, fallbackOracle.stalenessThreshold);

                    if (isGoodFallbackResponse) {
                        _setMarketPriceSource(PriceSource.fallbackOracle);
                        _storeResponse(fallbackResponse);
                        return (fallbackResponse.price, fallbackResponse.success);
                    } else {
                         // if both oracles are bad, shutdown the price feed and revert to last good price
                        _setMarketPriceSource(PriceSource.lastGoodPrice);
                        // market oracle has failed so success is false
                        return (lastGoodMarketPrice, false);
                    }
                } else {
                     // if the fallback oracle is not set, shutdown the price feed and revert to last good price
                     _setMarketPriceSource(PriceSource.lastGoodPrice);
                     return (lastGoodMarketPrice, false);
                }
        }
        
        // if the price feed is using the fallback oracle and the fallback oracle is set-
        if(marketPriceSource == PriceSource.fallbackOracle) {
            // get fallback response
            Response memory fallbackResponse = _fetchPriceFromFallbackOracle();
            bool isGoodFallbackResponse = isGoodResponse(fallbackResponse, fallbackOracle.stalenessThreshold);

            // get primary response
            Response memory primaryResponse = _fetchPriceFromPrimaryOracle();

            bool safeToUsePrimary = isGoodResponse(primaryResponse, primaryOracle.stalenessThreshold) &&
            isGoodResponse(fallbackResponse, fallbackOracle.stalenessThreshold) &&
            _withinDeviationThreshold(primaryResponse.price, fallbackResponse.price, C.FALLBACK_PRIMARY_DEVIATION_THRESHOLD);

                if (safeToUsePrimary) {
                    // if the primary oracle is good and within the deviation threshold, set the market price source to the primary oracle and return the primary response
                    _setMarketPriceSource(PriceSource.primaryOracle);
                    _storeResponse(primaryResponse);
                    return (primaryResponse.price, primaryResponse.success);
                } else if (isGoodFallbackResponse && !safeToUsePrimary) {
                    // if the primary oracle is not safe to use, return fallback response
                    _storeResponse(fallbackResponse);
                    return (fallbackResponse.price, fallbackResponse.success);            
                } else {
                    // if primary and fallback are both bad, shutdown the price feed and revert to last good price
                    _setMarketPriceSource(PriceSource.lastGoodPrice);
                    return (lastGoodMarketPrice, false);
                }
        }

        // oracle not using primary or fallback oracle, in shutdown state, return last good response
        return (lastGoodMarketPrice, false);
    }
    
    // --- Overrides ---
    /// @notice must override all functions below with the library for the selected oracle
    
    // must override with the library of the primary oracle
    function _fetchPriceFromPrimaryOracle() internal virtual returns (Response memory);

    // must override with the library of the fallback oracle
    function _fetchPriceFromFallbackOracle() internal virtual returns (Response memory);

    // --- Helper functions ---

    function isGoodResponse(IPriceFeed.Response memory _response, uint256 _staleThreshold) public view returns (bool) {
        return _response.success 
            && _response.price > 0 
            && _response.lastUpdated > 0 
            && block.timestamp - _response.lastUpdated < _staleThreshold;
    }

    function _setMarketPriceSource(PriceSource _marketPriceSource) internal virtual {
        if (marketPriceSource != _marketPriceSource) {
            marketPriceSource = _marketPriceSource; 
            emit MarketPriceSourceChanged(marketPriceSource);
        }

        if (_marketPriceSource == PriceSource.lastGoodPrice) {
            emit ShutdownInitiated("Market Oracle Failure", block.number);
        }
    }

    function _storeResponse(Response memory _response) internal {
        lastGoodMarketPrice = _response.price;
        emit LastGoodMarketPriceUpdated(_response.price, _response.lastUpdated);
    }

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
}

