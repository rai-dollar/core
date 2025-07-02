// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../../PriceFeeds/PriceFeedBase.sol";
import "../../PriceFeeds/Parsers/ChainlinkParser.sol";
import "../../PriceFeeds/Parsers/Api3Parser.sol";

contract PriceFeedBaseTester is PriceFeedBase {
    Response public lastGoodPriceResponse;

    event PriceResponseSaved(uint256 price, uint256 lastUpdated);
    event PriceSourceChanged(PriceSource priceSource, uint256 timestamp);

    PriceSource public priceSource;

    constructor(OracleConfig memory _primaryOracle, address _token, uint256 _deviationThreshold) PriceFeedBase(_primaryOracle, _token, _deviationThreshold) {}

    /// @notice must override the following function with oracle / collateral specific logic

    // --- Oracle Overrides ---
    
    // external function that fetches the price from the primary or fallback oracle
    function fetchPrice(bool /*_isRedemption*/) external override returns (uint256 price){
        Response memory response = _fetchPrimaryMarketOraclePrice();
        bool primaryIsGood = isGoodResponse(response, primaryMarketOracle.stalenessThreshold);
        if (primaryIsGood) {
            _setMarketPriceSource(PriceSource.primaryOracle);
            _storeLastGoodMarketResponse(response);
            return response.price;
        } else {
            _setMarketPriceSource(PriceSource.fallbackOracle);
            Response memory fallbackResponse = _fetchFallbackMarketOraclePrice();
            bool fallbackIsGood = isGoodResponse(fallbackResponse, fallbackMarketOracle.stalenessThreshold);
            if (fallbackIsGood) {
                _storeLastGoodMarketResponse(fallbackResponse);
                return fallbackResponse.price;
            } else {
                _setMarketPriceSource(PriceSource.lastGoodResponse);
                return 0;
            }
        }
    }

    function fetchPrimaryPrice() external returns (uint256 price, bool success) {
        Response memory response = _fetchPrimaryMarketOraclePrice();
        return (response.price, response.success);
    }
    
    function fetchFallbackPrice() external returns (uint256 price, bool success) {
        Response memory response = _fetchFallbackMarketOraclePrice();
        return (response.price, response.success);
    }

    // primary oracle response
    function _fetchPrimaryMarketOraclePrice() internal override returns (Response memory) {
        return ChainlinkParser.getResponse(primaryMarketOracle.oracle);
    }

    // fallback oracle response
    function _fetchFallbackMarketOraclePrice() internal override returns (Response memory) {
        return Api3Parser.getResponse(fallbackMarketOracle.oracle);
    }
    
    function marketPrimaryIsSet() external view returns (bool) {
        return _marketPrimaryIsSet();
    }

    function marketFallbackIsSet() external view returns (bool) {
        return _marketFallbackIsSet();
    }
    
    function setMarketPriceSource(PriceSource _marketPriceSource) external {
        _setMarketPriceSource(_marketPriceSource);
    }

    function storeLastGoodMarketResponse(Response memory _response) external {
        _storeLastGoodMarketResponse(_response);
    }
    
    function withinDeviationThreshold(uint256 _priceToCheck, uint256 _referencePrice) external view returns (bool) {
        return _withinDeviationThreshold(_priceToCheck, _referencePrice, deviationThreshold);
    }
    
}