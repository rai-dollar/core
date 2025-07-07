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
    Oracle public primaryMarketOracle;
    // this is the fallback in case the primary oracle fails
    Oracle public fallbackMarketOracle;
    // this is the base token for which the price is being fetched
    IERC20 public token;

    uint256 public deviationThreshold;

    // The last good price returned by any oracle
    Response public lastGoodMarketResponse;
    
    // Where the price feed is getting its price: primaryMarketOracle, fallbackMarketOracle, or shutdown
    PriceSource public marketPriceSource;
    
    event MarketPriceSourceChanged(PriceSource marketPriceSource);
    event LastGoodMarketResponseUpdated(uint256 price, uint256 lastUpdated);
    event ShutdownInitiated(string reason, uint256 timestamp);
    
    constructor(OracleConfig memory _marketOracleConfig, address _token, uint256 _deviationThreshold) {
        primaryMarketOracle.oracle = _marketOracleConfig.primaryOracle;
        primaryMarketOracle.stalenessThreshold = _marketOracleConfig.primaryStalenessThreshold;

        fallbackMarketOracle.oracle = _marketOracleConfig.fallbackOracle;
        fallbackMarketOracle.stalenessThreshold = _marketOracleConfig.fallbackStalenessThreshold;

        token = IERC20(_token);
        assert(token.decimals() != 0);
        marketPriceSource = PriceSource.primaryOracle;
        deviationThreshold = _deviationThreshold;
    }

    // --- Functions ---
    /// @notice must override all functions below with the library for the selected oracle

    // must override with specific logic for each collateral type and oracle combination
    function fetchPrice(bool _isRedemption) external virtual returns (uint256);
   
    // must override with the library of the primary oracle
    function _fetchPrimaryMarketOraclePrice() internal virtual returns (Response memory);

    // must override with the library of the fallback oracle (if fallback oracle is set)
    function _fetchFallbackMarketOraclePrice() internal virtual returns (Response memory);

    // --- Helper functions ---
    function _marketPrimaryIsSet() internal view returns (bool) {
        return primaryMarketOracle.oracle != address(0) && primaryMarketOracle.stalenessThreshold > 0;
    }

    function _marketFallbackIsSet() internal view returns (bool) {
        return fallbackMarketOracle.oracle != address(0) && fallbackMarketOracle.stalenessThreshold > 0;
    }

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

                if (_marketPriceSource == PriceSource.lastGoodResponse) {
                _shutdownAndSwitchToLastGoodPrice();
                }
        }
    }

    function _shutdownAndSwitchToLastGoodResponse() internal virtual {
        // TODO:include shutdown logic here

        emit ShutdownInitiated("Market Oracle Failure", block.timestamp);
    }

    function _storeLastGoodMarketResponse(Response memory _response) internal {
        lastGoodMarketResponse = _response;
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

