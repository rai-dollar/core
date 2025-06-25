// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IPriceFeed} from "./Interfaces/IPriceFeed.sol";
import {LiquityMath} from "./Common/LiquityMath.sol";
import {IERC20} from "./Interfaces/IERC20.sol";
import {Constants as C} from "./Common/Constants.sol";

/*
* PriceFeed for mainnet deployment, to be connected to Chainlink's live ETH:USD aggregator reference 
* contract, and a wrapper contract TellorCaller, which connects to TellorMaster contract.
*
* The PriceFeed uses Chainlink as primary oracle, and Tellor as fallback. It contains logic for
* switching oracles based on oracle failures, timeouts, and conditions for returning to the primary
* Chainlink oracle.
*/
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
    Response public lastGoodResponse;
    
    // Where the price feed is getting its price: primaryOracle, fallbackOracle, or shutdown
    PriceSource public marketPriceSource;
    
    event MarketPriceSourceChanged(PriceSource marketPriceSource);
    event LastGoodMarketResponseUpdated(uint256 price, uint256 lastUpdated);
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
    function _fetchMarketOraclePrice() internal returns (Response memory response){
        // if the price feed is in a shutdown state, return the last good price
        if (marketPriceSource == PriceSource.lastGoodResponse) {
            return lastGoodResponse;
        }

        // if the price feed is using the primary oracle
        if(marketPriceSource == PriceSource.primaryOracle) {
            // get primary response
        Response memory primaryResponse = _fetchPriceFromPrimaryOracle();
        bool isGoodPrimaryResponse = isGoodResponse(primaryResponse, primaryOracle.stalenessThreshold);
        
        if (isGoodPrimaryResponse) {
            _setMarketPriceSource(PriceSource.primaryOracle);
            _storeResponse(primaryResponse);
            
            return primaryResponse;
        } else {
            // if primary is not good, get fallback response
            Response memory fallbackResponse = _fetchPriceFromFallbackOracle();
            bool isGoodFallbackResponse = isGoodResponse(fallbackResponse, fallbackOracle.stalenessThreshold);

            if (isGoodFallbackResponse) {
                _setMarketPriceSource(PriceSource.fallbackOracle);
                _storeResponse(fallbackResponse);
                return fallbackResponse;
            } else {
                // if both oracles are bad, shutdown the price feed and revert to last good price
                _setMarketPriceSource(PriceSource.lastGoodResponse);
                return lastGoodResponse;
            }
        }
        }
        // if the price feed is using the fallback oracle
        if(marketPriceSource == PriceSource.fallbackOracle) {
        // get fallback response
        Response memory fallbackResponse = _fetchPriceFromFallbackOracle();
        bool isGoodFallbackResponse = isGoodResponse(fallbackResponse, fallbackOracle.stalenessThreshold);

        // get primary response
        Response memory primaryResponse = _fetchPriceFromPrimaryOracle();

        bool isGoodPrimaryResponse = isGoodResponse(primaryResponse, primaryOracle.stalenessThreshold) && _withinDeviationThreshold(primaryResponse.price, fallbackResponse.price, deviationThreshold);

        if (isGoodPrimaryResponse) {
            // if the primary oracle is good and within the deviation threshold, set the market price source to the primary oracle and return the primary response
            _setMarketPriceSource(PriceSource.primaryOracle);
            _storeResponse(primaryResponse);
            return primaryResponse;
        } else if (isGoodFallbackResponse && !isGoodPrimaryResponse) {
            // if the primary oracle is not good, return fallback response
            _storeResponse(fallbackResponse);
            return fallbackResponse;            
        } else {
            // if primary and fallback are both bad, shutdown the price feed and revert to last good price
            _setMarketPriceSource(PriceSource.lastGoodResponse);
            return lastGoodResponse;
        }
        } else {
            // oracle in shutdown state, return last good response
            return lastGoodResponse;
        }
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

        if (_marketPriceSource == PriceSource.lastGoodResponse) {
            emit ShutdownInitiated("Market Oracle Failure", block.number);
        }
    }

    function _storeResponse(Response memory _response) internal {
        lastGoodResponse = _response;
        emit LastGoodMarketResponseUpdated(_response.price, _response.lastUpdated);
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

