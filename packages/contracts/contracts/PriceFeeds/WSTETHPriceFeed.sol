// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {CompositePriceFeedBase} from "./CompositePriceFeedBase.sol";
import {ChainlinkParser} from "./Parsers/ChainlinkParser.sol";
import {Api3Parser} from "./Parsers/Api3Parser.sol";

import "hardhat/console.sol";

interface IWSTEthRateProvider {
    function stEthPerToken() external view returns (uint256);
}

contract WSTETHPriceFeed is CompositePriceFeedBase {
    event WstEthUsdPriceSourceChanged(PriceSource wethUsdPriceSource, uint256 timestamp);
    event OraclePricesAboveMaxDeviation(uint256 primaryPrice, uint256 fallbackPrice, uint256 primaryTimestamp, uint256 fallbackTimestamp, uint256 deviationThreshold);

    PriceSource public wethUsdPriceSource;

   constructor(
    OracleConfig memory _marketOracleConfig, 
    OracleConfig memory _ethUsdOracleConfig, 
    address _token, 
    address _rateProvider, 
    uint256 _deviationThreshold
    ) CompositePriceFeedBase(_marketOracleConfig, _ethUsdOracleConfig, _token, _rateProvider, _deviationThreshold) {
    // ensure primary market oracle is set
    if(!_marketPrimaryIsSet()) {
        revert("Primary market oracle must be set");
    }

    // ensure composite primary oracle is set
    if(!_compositePrimaryIsSet()) {
        revert("Eth usd primary oracle must be set");
    }

    // ensure composite fallback oracle is set
    if(!_compositeFallbackIsSet()) {
        revert("Eth usd fallback oracle must be set");
    }

    // ensure deviation threshold is valid
    if(_deviationThreshold == 0) {
        revert("Invalid deviation threshold");
    }

    // ensure valid initial settings
    Response memory primaryMarketResponse = _getPrimaryMarketOracleResponse();
    Response memory primaryCompositeResponse = _getPrimaryCompositeOracleResponse();
    Response memory fallbackCompositeResponse = _getFallbackCompositeOracleResponse();
    Response memory canonicalRateResponse = _fetchCanonicalRate();
    
    if(
        primaryMarketResponse.success &&
        primaryCompositeResponse.success &&
        fallbackCompositeResponse.success &&
        canonicalRateResponse.success
           ) {
        Response memory wstEthUsdResponse = _fetchWstEthUsdResponse(false);
                
        _setMarketPriceSource(PriceSource.primaryOracle);
        _setCompositePriceSource(PriceSource.primaryOracle);
        _setWethUsdPriceSource(PriceSource.primaryOracle);

        _saveLastGoodResponse(wstEthUsdResponse);
    } else {
        revert("Invalid oracle configuration");
    }

   }


    function fetchPrice(bool _isRedemption) external override returns (uint256 price) {
    if (wethUsdPriceSource == PriceSource.lastGoodResponse) {
        return lastGoodResponse.price;
    }
       
       Response memory wstEthUsdResponse = _fetchWstEthUsdResponse(_isRedemption);
       
        return wstEthUsdResponse.price;
    }

    function _fetchWstEthUsdResponse(bool _isRedemption) internal returns (Response memory _wstEthUsdResponse) {
        // since we are using only one steth/usd oracle, we can use the primary market oracle response
        Response memory stEthUsdPriceResponse = _getPrimaryMarketOracleResponse();
        Response memory ethUsdPriceResponse = _fetchEthUsdPrice();
        Response memory stethPerWstethResponse = _fetchCanonicalRate();

        //if canonical rate fails or eth/usd is not good, shutdown everything
        if (!stethPerWstethResponse.success || !ethUsdPriceResponse.success) {
            _shutdownAndSwitchToLastGoodResponse(FailureType.MULTIPLE_FEED_FAILURES);
            return lastGoodResponse;
        }

        Response memory wstEthUsdResponse;
      
        // if market oracle and composite oracle are good, calculate the wsteth/usd price 
        if (stEthUsdPriceResponse.success && ethUsdPriceResponse.success) {
            bool withinDeviationThreshold = _withinDeviationThreshold(stEthUsdPriceResponse.price, ethUsdPriceResponse.price, deviationThreshold);
            // if redemption, check if the stEthUsdPrice and ethUsdPrice are within the deviation threshold
            if (_isRedemption && withinDeviationThreshold) {
                // if steth/usd and eth/usd are within the deviation threshold, use the redemption max price
                    wstEthUsdResponse = _getMaxRedemptionPrice(stEthUsdPriceResponse, ethUsdPriceResponse, stethPerWstethResponse);
                
            } else if (_isRedemption && !withinDeviationThreshold) {
                // if not within the deviation threshold, use eth/usd price for calculation
                wstEthUsdResponse.price = _getRedemptionPrice(ethUsdPriceResponse.price, stethPerWstethResponse.price);
                wstEthUsdResponse.success = true;
                wstEthUsdResponse.lastUpdated = stethPerWstethResponse.lastUpdated;

            } else if (!_isRedemption && withinDeviationThreshold) {
                // if not a redemption and within the deviation threshold, use steth/usd price for calculation
                wstEthUsdResponse.price = _getRedemptionPrice(stEthUsdPriceResponse.price, stethPerWstethResponse.price);
                wstEthUsdResponse.success = true;
                wstEthUsdResponse.lastUpdated = stethPerWstethResponse.lastUpdated;
            } else {
                // if not redemption and not within the deviation threshold, use eth/usd price for calculation
                wstEthUsdResponse.price = _getRedemptionPrice(ethUsdPriceResponse.price, stethPerWstethResponse.price);
                wstEthUsdResponse.success = true;
                wstEthUsdResponse.lastUpdated = ethUsdPriceResponse.lastUpdated;
            }

            // if the wsteth/usd price is good, save it if not, shutdown and return last good response
            if (wstEthUsdResponse.success) {
                _saveLastGoodResponse(wstEthUsdResponse);
            } else {
                _shutdownAndSwitchToLastGoodResponse(FailureType.MULTIPLE_FEED_FAILURES);
                wstEthUsdResponse = lastGoodResponse;  
                wstEthUsdResponse.success = false;
            }
        } else if (!stEthUsdPriceResponse.success && ethUsdPriceResponse.success) {
            // if market oracle is not good and composite oracle is good, use the eth/usd price and use fallback
            wstEthUsdResponse.price = _getRedemptionPrice(ethUsdPriceResponse.price, stethPerWstethResponse.price);
            wstEthUsdResponse.success = false;
            wstEthUsdResponse.lastUpdated = ethUsdPriceResponse.lastUpdated;

            _saveLastGoodResponse(wstEthUsdResponse);

            _setWethUsdPriceSource(PriceSource.fallbackOracle);
        } else {
            //return last good response and use last good response for everything
            _shutdownAndSwitchToLastGoodResponse(FailureType.MULTIPLE_FEED_FAILURES);
            wstEthUsdResponse = lastGoodResponse;  
            if(wstEthUsdResponse.success != false){
                wstEthUsdResponse.success = false;
            }
        }

        return wstEthUsdResponse;
    }

    // since we are using a fallback eth/usd oracle, we need to add logic to handle the fallback oracle
    function _fetchEthUsdPrice() internal returns (Response memory _ethUsdPriceResponse) {
        if(compositePriceSource == PriceSource.primaryOracle) {
            // fetch ethUsdPrice from primary oracle
            Response memory ethUsdPriceResponse = _getPrimaryCompositeOracleResponse();

            // if the primary ethUsdPrice is good, return it
            if (ethUsdPriceResponse.success) {
                return ethUsdPriceResponse;
            } else {
                // if the ethUsdPrice is not good, check if the fallback oracle is good
                Response memory ethUsdPriceResponseFallback = _getFallbackCompositeOracleResponse();
                // if the fallback ethUsdPrice is good, save it, set price source to fallback and return it
                if (ethUsdPriceResponseFallback.success) {
                    _setCompositePriceSource(PriceSource.fallbackOracle);
                    return ethUsdPriceResponseFallback;
                    
                } else {
                     // if the fallback ethUsdPrice is not good, set shut down price feed and return
                     // an empty response with no value and success false
                    _shutdownAndSwitchToLastGoodResponse(FailureType.COMPOSITE_ORACLE_FAILURE);
                    return _ethUsdPriceResponse;
                }
            }
        } 
        
        // if fallback is being used
        if (compositePriceSource == PriceSource.fallbackOracle) {
           Response memory ethUsdPriceResponseFallback = _getFallbackCompositeOracleResponse();
           Response memory ethUsdPriceResponse = _getPrimaryCompositeOracleResponse();
           
           // check primary and fallback deviation
           bool withinDeviationThreshold = _withinDeviationThreshold(
                ethUsdPriceResponse.price,
                ethUsdPriceResponseFallback.price,
                deviationThreshold);

           // if primary oracle is now good and fallback is good set composite price source to primary
           // and return max of the two responses
           if (ethUsdPriceResponse.success && ethUsdPriceResponseFallback.success && withinDeviationThreshold) {
                _setCompositePriceSource(PriceSource.primaryOracle);
                // return the max of the two responses
                Response memory ethUsdPriceResponse = ethUsdPriceResponse.price > ethUsdPriceResponseFallback.price ?
                ethUsdPriceResponse : ethUsdPriceResponseFallback;

                return ethUsdPriceResponse;
            // if not within the deviation threshold but both price feeds are good, use the max price to protect protocol
           } else if (ethUsdPriceResponse.success && ethUsdPriceResponseFallback.success && !withinDeviationThreshold) {
                emit OraclePricesAboveMaxDeviation(
                    ethUsdPriceResponse.price, ethUsdPriceResponseFallback.price,
                    ethUsdPriceResponse.lastUpdated, ethUsdPriceResponseFallback.lastUpdated,
                    deviationThreshold
                    );
                return ethUsdPriceResponse.price > ethUsdPriceResponseFallback.price ? ethUsdPriceResponse : ethUsdPriceResponseFallback;
           } else if(!ethUsdPriceResponse.success && ethUsdPriceResponseFallback.success) {
                // if fallback is good and primary is not, keep price source as fallback and return fallback response
                return ethUsdPriceResponseFallback;
           } else if(ethUsdPriceResponse.success && !ethUsdPriceResponseFallback.success) {
                // if primary is good and fallback is not, set price source to primary and return primary response
                _setCompositePriceSource(PriceSource.primaryOracle);
                return ethUsdPriceResponse;
           } else {
                // if both are not good, shut down price feed and return an empty response with no value and success false
                _shutdownAndSwitchToLastGoodResponse(FailureType.COMPOSITE_ORACLE_FAILURE);
                Response memory emptyResponse;
                return emptyResponse;
           }
        } 

        assert(compositePriceSource == PriceSource.lastGoodResponse);
        // since we're not storing the primary or composite oracle responses, lastGood will be empty indicating a failure
        return _ethUsdPriceResponse;
    }

    // --- Oracle Overrides ---

    function _fetchPrimaryMarketOraclePrice() internal view override returns (Response memory) {
        return ChainlinkParser.getResponse(primaryMarketOracle.oracle);
    }

    function _fetchFallbackMarketOraclePrice() internal view override returns (Response memory) {
        revert ("Fallback market oracle not supported");
    }

    function _fetchPrimaryCompositeOraclePrice() internal view override returns (Response memory) {
        return ChainlinkParser.getResponse(primaryCompositeOracle.oracle);
    }

    function _fetchFallbackCompositeOraclePrice() internal view override returns (Response memory) {
        return Api3Parser.getResponse(fallbackCompositeOracle.oracle);
    }

    // --- Internal Functions ---

    // overridden from composite base to return the correct response
    function _fetchCanonicalRate() internal override view returns (Response memory response) {
        uint256 gasBefore = gasleft();

        try IWSTEthRateProvider(rateProvider).stEthPerToken() returns (uint256 stEthPerWstEth) {

            response.price = stEthPerWstEth;
            response.success = stEthPerWstEth != 0;
            response.lastUpdated = block.timestamp;
            return response;
        } catch {
            // Require that enough gas was provided to prevent an OOG revert in the external call
            // causing a shutdown. Instead, just revert. Slightly conservative, as it includes gas used
            // in the check itself.
            if (gasleft() <= gasBefore / 64) revert InsufficientGasForExternalCall();


            // If call to exchange rate reverted for another reason, return success = false
            return response;
        }
    }

    // sets the price source for this price feed
    function _setWethUsdPriceSource(PriceSource _wethUsdPriceSource) internal {
        if (wethUsdPriceSource != _wethUsdPriceSource) {
            wethUsdPriceSource = _wethUsdPriceSource;
            emit WstEthUsdPriceSourceChanged(_wethUsdPriceSource, block.timestamp);
        }
    }

    // overridden from composite base and PriceFeedBase to shut down all price sources in the event of a failure
    function _shutdownAndSwitchToLastGoodResponse(FailureType _failureType) internal override  {
        lastGoodResponse.success = false;
        _setWethUsdPriceSource(PriceSource.lastGoodResponse);
        _setCompositePriceSource(PriceSource.lastGoodResponse);
        _setMarketPriceSource(PriceSource.lastGoodResponse);
        emit ShutdownInitiated(_failureType, block.timestamp);
    }

}
