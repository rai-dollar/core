// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../PriceFeeds/PriceFeedBase.sol";
import "../PriceFeeds/Parsers/ChainlinkParser.sol";

contract PriceFeedBaseTester is PriceFeedBase {
    Response public lastGoodPriceResponse;

    event PriceResponseSaved(uint256 price, uint256 lastUpdated);
    event PriceSourceChanged(PriceSource priceSource, uint256 timestamp);

    PriceSource public priceSource;

    constructor(address _primaryOracle, address _fallbackOracle, address _token) PriceFeedBase(_primaryOracle, _fallbackOracle, _token) {}

    /// @notice must override the following function with oracle / collateral specific logic

    // --- Oracle Overrides ---
    
    // external function that fetches the price from the primary or fallback oracle
    function fetchPrice(bool _isRedemption) external override returns (uint256 price, bool success){
            if (wethUsdPriceSource == PriceSource.lastGoodResponse) {
        return lastGoodWstEthUsdResponse.price;
    }

        Response memory primaryOracleResponse = _fetchPriceFromPrimaryOracle();
        Response memory fallbackOracleResponse = _fetchPriceFromFallbackOracle();

        uint256 primaryOracleStalenessThreshold = primaryOracle.stalenessThreshold;
        bool primaryOracleIsGood = isGoodResponse(primaryOracleResponse, primaryOracleStalenessThreshold);

        uint256 fallbackOracleStalenessThreshold = fallbackOracle.stalenessThreshold;
        bool fallbackOracleIsGood = isGoodResponse(fallbackOracleResponse, fallbackOracleStalenessThreshold);
        
        Response memory priceResponse;
      
        // if market oracle and composite oracle are good, calculate the wsteth/usd price 
        if (primaryOracleIsGood && fallbackOracleIsGood) {
            bool withinDeviationThreshold = _withinDeviationThreshold(primaryOracleResponse.price, fallbackOracleResponse.price, deviationThreshold);
            // if redemption, check if the stEthUsdPrice and ethUsdPrice are within the deviation threshold
            if (_isRedemption && withinDeviationThreshold) {
                // if steth/usd and eth/usd are within the deviation threshold, use the redemption max price
                    priceResponse = _getMaxRedemptionPrice(primaryOracleResponse, fallbackOracleResponse);
                
            } else if (_isRedemption && !withinDeviationThreshold) {
                // if not within the deviation threshold, use eth/usd price for calculation
                priceResponse.price = _getRedemptionPrice(fallbackOracleResponse.price, primaryOracleResponse.price);
                priceResponse.success = true;
                priceResponse.lastUpdated = primaryOracleResponse.lastUpdated;

            } else if (!_isRedemption && withinDeviationThreshold) {
                // if not a redemption and within the deviation threshold, use steth/usd price for calculation
                priceResponse.price = _getRedemptionPrice(primaryOracleResponse.price, fallbackOracleResponse.price);
                priceResponse.success = true;
                priceResponse.lastUpdated = primaryOracleResponse.lastUpdated;
            } else {
                // if not redemption and not within the deviation threshold, use eth/usd price for calculation
                priceResponse.price = _getRedemptionPrice(fallbackOracleResponse.price, primaryOracleResponse.price);
                priceResponse.success = true;
                priceResponse.lastUpdated = fallbackOracleResponse.lastUpdated;
            }

            // if the wsteth/usd price is good, save it if not, shutdown and return last good response
            if (isGoodResponse(priceResponse, fallbackOracleStalenessThreshold)) {
                _saveLastGoodPriceResponse(priceResponse);
            } else {
                _setPriceSource(PriceSource.lastGoodResponse);
                priceResponse = lastGoodPriceResponse;  
                priceResponse.success = false;
            }
        } else if (!primaryOracleIsGood && fallbackOracleIsGood) {
            // if market oracle is not good and composite oracle is good, use the eth/usd price and shut down
            priceResponse.price = _getRedemptionPrice(fallbackOracleResponse.price, primaryOracleResponse.price);
            priceResponse.success = false;
            priceResponse.lastUpdated = fallbackOracleResponse.lastUpdated;

            _saveLastGoodPriceResponse(priceResponse);

            _setPriceSource(PriceSource.lastGoodResponse);
        } else {
            //return last good response and shut down everything
            _setPriceSource(PriceSource.lastGoodResponse);
            priceResponse = lastGoodPriceResponse;  
            priceResponse.success = false;
        }

        return priceResponse.price;
    }

    // primary oracle response
    function _fetchPriceFromPrimaryOracle() internal override returns (Response memory) {
        return ChainlinkParser.getResponse(primaryOracle);
    }

    // fallback oracle response
    function _fetchPriceFromFallbackOracle() internal override returns (Response memory) {
        return ChainlinkParser.getResponse(fallbackOracle);
    }
}