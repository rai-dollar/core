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

    // The last good price returned by any oracle
    Response public lastGoodResponse;
    
    // Where the price feed is getting its price: primaryOracle, fallbackOracle, or shutdown
    PriceSource public marketPriceSource;
    
    event MarketPriceSourceChanged(PriceSource marketPriceSource);
    event LastGoodMarketResponseUpdated(uint256 price, uint256 lastUpdated);
    
    constructor(OracleConfig memory _marketOracleConfig, address _token) {
        primaryOracle.oracle = _marketOracleConfig.primaryOracle;
        primaryOracle.stalenessThreshold = _marketOracleConfig.primaryStalenessThreshold;

        fallbackOracle.oracle = _marketOracleConfig.fallbackOracle;
        fallbackOracle.stalenessThreshold = _marketOracleConfig.fallbackStalenessThreshold;

        token = IERC20(_token);
        assert(token.decimals() != 0);
        marketPriceSource = PriceSource.primaryOracle;
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

        Response memory primaryResponse = _fetchPriceFromPrimaryOracle();
        bool isGoodPrimaryResponse = isGoodResponse(primaryResponse, primaryOracle.stalenessThreshold);
        
        if (isGoodPrimaryResponse) {
            _setMarketPriceSource(PriceSource.primaryOracle);
            _storeResponse(primaryResponse);
            
            return primaryResponse;
        } 

        Response memory fallbackResponse = _fetchPriceFromFallbackOracle();
        bool isGoodFallbackResponse = isGoodResponse(fallbackResponse, fallbackOracle.stalenessThreshold);

        if (isGoodFallbackResponse) {
            _setMarketPriceSource(PriceSource.fallbackOracle);
            _storeResponse(fallbackResponse);
            
            return fallbackResponse;
        }

        // if primary and fallback are both bad, shutdown the price feed and revert to last good price
        _setMarketPriceSource(PriceSource.lastGoodResponse);
        return lastGoodResponse;
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

    function _setMarketPriceSource(PriceSource _marketPriceSource) internal virtual{
        if (marketPriceSource != _marketPriceSource) {
            marketPriceSource = _marketPriceSource; 
            emit MarketPriceSourceChanged(marketPriceSource);
        }
    }

    function _storeResponse(Response memory _response) internal {
        lastGoodResponse = _response;
        emit LastGoodMarketResponseUpdated(_response.price, _response.lastUpdated);
    }


}

