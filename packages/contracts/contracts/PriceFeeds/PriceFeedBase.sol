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

    // The last good price returned.  this is the final calculated price that is returned to the user.
    Response public lastGoodResponse;
    
    // Determines where the PriceFeed sources data from. Possible states:
    // - primary: Uses the primary price calcuation, which depends on the specific feed
    // - fallback: Uses using the fallback oracle in case of primary oracle failure
    // - lastGoodPrice: the price feed is shut down and will only return the last good price recorded
    PriceSource public marketPriceSource;
    
    event MarketPriceSourceChanged(PriceSource marketPriceSource);
    event LastGoodResponseUpdated(uint256 price, uint256 lastUpdated);
    event ShutdownInitiated(FailureType failureType, uint256 timestamp);
    
    constructor(OracleConfig memory _marketOracleConfig, address _token, uint256 _deviationThreshold) {
        primaryMarketOracle.oracle = _marketOracleConfig.primaryOracle;
        primaryMarketOracle.stalenessThreshold = _marketOracleConfig.primaryStalenessThreshold;

        fallbackMarketOracle.oracle = _marketOracleConfig.fallbackOracle;
        fallbackMarketOracle.stalenessThreshold = _marketOracleConfig.fallbackStalenessThreshold;

        deviationThreshold = _deviationThreshold;

        token = IERC20(_token);
        assert(token.decimals() != 0);

        // set market price source
        marketPriceSource = PriceSource.primaryOracle;
    }
    // --- Overrides ---

    /// @notice must override with specific logic for each collateral type and oracle combination
    function fetchPrice(bool _isRedemption) external virtual returns (uint256);

    /// @notice must override all functions below with the library for the selected oracle
    function _fetchPrimaryMarketOraclePrice() internal virtual returns (Response memory);

    function _fetchFallbackMarketOraclePrice() internal virtual returns (Response memory);


    // --- Functions ---
    function _getPrimaryMarketOracleResponse() internal returns (Response memory) {
           Response memory response = _fetchPrimaryMarketOraclePrice();

           response.success = isGoodResponse(response, primaryMarketOracle.stalenessThreshold);

           return response;
    }

    function _getFallbackMarketOracleResponse() internal returns (Response memory) {
          Response memory response = _fetchFallbackMarketOraclePrice();

           response.success = isGoodResponse(response, fallbackMarketOracle.stalenessThreshold);

           return response;
    }

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

    // deviation threshold is per collateral type
    function _withinDeviationThreshold(uint256 _priceToCheck, uint256 _referencePrice, uint256 _deviationThreshold)
        internal
        pure
        returns (bool)
    {
        // Calculate the price deviation of the oracle market price relative to the canonical price
        uint256 max = _referencePrice * (C.DECIMAL_PRECISION + _deviationThreshold) / 1e18;
        uint256 min = _referencePrice * (C.DECIMAL_PRECISION - _deviationThreshold) / 1e18;

        if(min == 0 || max == 0) {
            return false;
        }

        return _priceToCheck >= min && _priceToCheck <= max;
    }
    
    function _saveLastGoodResponse(Response memory _response) internal {
        if (_response.success) {
            lastGoodResponse = _response;
            emit LastGoodResponseUpdated(_response.price, _response.lastUpdated);
        }
    }
    
    /// TODO: Are these necessary or should this be done in the oracle?
    function _setMarketPriceSource(PriceSource _marketPriceSource) internal virtual {
        if (marketPriceSource != _marketPriceSource) {
            marketPriceSource = _marketPriceSource; 
            emit MarketPriceSourceChanged(marketPriceSource);
        }
    }

    // @note must override in child contract to handle full shutdown logic
    function _shutdownAndSwitchToLastGoodResponse(FailureType _failureType) internal virtual {
        // set last good response to false to indicate that oracle response is not good
        lastGoodResponse.success = false;
        _setMarketPriceSource(PriceSource.lastGoodResponse);
        emit ShutdownInitiated(_failureType, block.timestamp);
    }

    function _storeLastGoodResponse(Response memory _response) internal {
        lastGoodResponse = _response;
        emit LastGoodResponseUpdated(_response.price, _response.lastUpdated);
    }
}

