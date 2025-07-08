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
    event EthUsdPricesAboveMaxDeviation(uint256 primaryPrice, uint256 fallbackPrice, uint256 primaryTimestamp, uint256 fallbackTimestamp, uint256 deviationThreshold);
    
    // possible states
    // 1. primaryOracle -> steth/usd * canonical rate -> wsteth/usd
    // 2. fallbackOracle -> eth/usd * canonical rate -> wsteth/usd
    // 3. lastGoodResponse -> shutdown returning last good wsteth/usd
    PriceSource public wethUsdPriceSource;

   constructor(
    OracleConfig memory _marketOracleConfig, 
    OracleConfig memory _ethUsdOracleConfig, 
    address _token, 
    address _rateProvider, 
    uint256 _deviationThreshold
    ) CompositePriceFeedBase(_marketOracleConfig, _ethUsdOracleConfig, _token, _rateProvider, _deviationThreshold) {
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
                
            _setMarketPriceSource(PriceSource.primaryOracle);
            _setCompositePriceSource(PriceSource.primaryOracle);
            _setWethUsdPriceSource(PriceSource.primaryOracle);

            Response memory wstEthUsdResponse = _fetchWstEthUsdResponse(false);
                    
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
        // if the price feed is shutdown, do not pass go, do not collect $200
        if (wethUsdPriceSource == PriceSource.lastGoodResponse) {
            return lastGoodResponse;
        }

        // since we are using only one steth/usd oracle, we can use the only primary market oracle response
        Response memory stEthUsdPriceResponse = _getPrimaryMarketOracleResponse();

        Response memory ethUsdPriceResponse = _fetchEthUsdPrice();
        Response memory stethPerWstethResponse = _fetchCanonicalRate();

        //if canonical rate fails or eth/usd is not good, shutdown everything
        if (!stethPerWstethResponse.success || !ethUsdPriceResponse.success) {
            _shutdownAndSwitchToLastGoodResponse(FailureType.MULTIPLE_FEED_FAILURES);
            return lastGoodResponse;
        }

        Response memory wstEthUsdResponse;
        
        if (wethUsdPriceSource == PriceSource.primaryOracle) {
            // if market oracle and composite oracle are good, calculate the wsteth/usd price 
            if (stEthUsdPriceResponse.success && ethUsdPriceResponse.success) {
                wstEthUsdResponse = _getStethUsdXCanonicalRate(stEthUsdPriceResponse, ethUsdPriceResponse, stethPerWstethResponse, _isRedemption);
            } else if (!stEthUsdPriceResponse.success && ethUsdPriceResponse.success) {
                // if market oracle is not good and composite oracle is good, use the eth/usd price and set price source to fallback
                // redemption doesn't matter here because we are already using the best eth/usd price
                wstEthUsdResponse = _getTokenXCanonicalRate(ethUsdPriceResponse, stethPerWstethResponse);
                // set price source to fallback oracle to indicate we are using eth/usd x canonical rate for all cases
                _setWethUsdPriceSource(PriceSource.fallbackOracle);
            } 
            // if both are not good wstEthUsdResponse.success will be false
        } 
        
        if (wethUsdPriceSource == PriceSource.fallbackOracle) {
            // check steth/usd price
            if (stEthUsdPriceResponse.success && ethUsdPriceResponse.success) {
                // if steth/usd is good, use the steth/usd and price and set price source to primary oracle
                wstEthUsdResponse = _getStethUsdXCanonicalRate(stEthUsdPriceResponse, ethUsdPriceResponse, stethPerWstethResponse, _isRedemption);
                // set price source to primary oracle to indicate we are using steth/usd x canonical rate for all cases
                _setWethUsdPriceSource(PriceSource.primaryOracle);
            } else if (!stEthUsdPriceResponse.success && ethUsdPriceResponse.success) {
                // if steth/usd is not good, use the eth/usd price and keep price source to fallback
                wstEthUsdResponse = _getTokenXCanonicalRate(ethUsdPriceResponse, stethPerWstethResponse);
            } 
            // if both are not good wstEthUsdResponse.success will be false
        } 

        // if the wsteth/usd price is good, save it if not, shutdown and return last good response
        if (wstEthUsdResponse.success) {
                _saveLastGoodResponse(wstEthUsdResponse);
            } else {
                // shutdown will set lastGoodResponse.success to false
                _shutdownAndSwitchToLastGoodResponse(FailureType.MULTIPLE_FEED_FAILURES);
                return lastGoodResponse;  
            }

        return wstEthUsdResponse;
    }

    function _getStethUsdXCanonicalRate(Response memory _stEthUsdPriceResponse, Response memory _ethUsdPriceResponse, Response memory _canonicalRateResponse, bool _isRedemption) internal view returns (Response memory stethUsdXCanonicalRateResponse) {
                    // check if the stEthUsdPrice and ethUsdPrice are within the deviation threshold
            bool withinDeviationThreshold = _withinDeviationThreshold(_stEthUsdPriceResponse.price, _ethUsdPriceResponse.price, deviationThreshold);
            if (_isRedemption && withinDeviationThreshold) {
                // if steth/usd and eth/usd are within the deviation threshold, use the redemption max price
                    stethUsdXCanonicalRateResponse.price = _getMaxRedemptionPrice(_stEthUsdPriceResponse, _ethUsdPriceResponse, _canonicalRateResponse);
                    stethUsdXCanonicalRateResponse.success = stethUsdXCanonicalRateResponse.price != 0;
                    stethUsdXCanonicalRateResponse.lastUpdated = stethUsdXCanonicalRateResponse.price == _stEthUsdPriceResponse.price ? _stEthUsdPriceResponse.lastUpdated : _ethUsdPriceResponse.lastUpdated;
            } else if (_isRedemption && !withinDeviationThreshold) {
                // if not within the deviation threshold, use eth/usd * canonical rate price for calculation
                stethUsdXCanonicalRateResponse = _getTokenXCanonicalRate(_ethUsdPriceResponse, _canonicalRateResponse);
            } else if (!_isRedemption && withinDeviationThreshold && _stEthUsdPriceResponse.success) {
                // if not a redemption and within the deviation threshold and steth/usd is good, use steth/usd price for calculation
                stethUsdXCanonicalRateResponse = _getTokenXCanonicalRate(_stEthUsdPriceResponse, _canonicalRateResponse);
            } else {
                // if not redemption and not within the deviation threshold, use eth/usd price for calculation
                stethUsdXCanonicalRateResponse = _getTokenXCanonicalRate(_ethUsdPriceResponse, _canonicalRateResponse);
            }
    }

    function _getTokenXCanonicalRate(Response memory _tokenPriceResponse, Response memory _canonicalRateResponse) internal view returns (Response memory tokenXCanonicalRateResponse) {
        tokenXCanonicalRateResponse.price = _getPrice(_tokenPriceResponse.price, _canonicalRateResponse.price);
        tokenXCanonicalRateResponse.success = tokenXCanonicalRateResponse.price != 0;
        tokenXCanonicalRateResponse.lastUpdated = _tokenPriceResponse.lastUpdated;
        return tokenXCanonicalRateResponse;
    }

    
    // since we are using a fallback eth/usd oracle, we have logic to handle the primary or fallback oracle usage
    function _fetchEthUsdPrice() internal returns (Response memory) {
        if(compositePriceSource == PriceSource.primaryOracle) {
            // fetch ethUsdPrice from primary oracle
            Response memory ethUsdPriceResponse = _getPrimaryCompositeOracleResponse();

            // if the primary ethUsdPrice is good, return it
            if (ethUsdPriceResponse.success) {
                return ethUsdPriceResponse;
            } else {
                // if the ethUsdPrice is not good, check if the fallback oracle is good
                Response memory ethUsdPriceResponseFallback = _getFallbackCompositeOracleResponse();
                // if the fallback ethUsdPrice is good, set price source to fallback and return it
                if (ethUsdPriceResponseFallback.success) {
                    _setCompositePriceSource(PriceSource.fallbackOracle);
                    return ethUsdPriceResponseFallback;
                    
                } else {
                     // if the fallback ethUsdPrice is not good, shut down price feed and return
                     // an empty response with no value and success false
                    _shutdownAndSwitchToLastGoodResponse(FailureType.COMPOSITE_ORACLE_FAILURE);
                    Response memory emptyResponse;
                    return emptyResponse;
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
           // if not within the deviation threshold but both price feeds are good, keep using fallback until prices are within the deviation threshold
           } else if (ethUsdPriceResponse.success && ethUsdPriceResponseFallback.success && !withinDeviationThreshold) {
                return ethUsdPriceResponseFallback;
           // if fallback is good and primary is not, keep price source as fallback and return fallback response
           } else if(!ethUsdPriceResponse.success && ethUsdPriceResponseFallback.success) {
                return ethUsdPriceResponseFallback;
           // if primary is good and fallback is not, set price source to primary and return primary response
           } else if(ethUsdPriceResponse.success && !ethUsdPriceResponseFallback.success) {
                _setCompositePriceSource(PriceSource.primaryOracle);
                return ethUsdPriceResponse;
                // if both are not good, shut down price feed and return an empty response with no value and success false
           } else {
                _shutdownAndSwitchToLastGoodResponse(FailureType.COMPOSITE_ORACLE_FAILURE);
                Response memory emptyResponse;
                return emptyResponse;
           }
        } 

        // if the composite price feed is shutdown return an empty response with no value and success false
        assert(compositePriceSource == PriceSource.lastGoodResponse);
        Response memory emptyResponse;
        return emptyResponse;
    }

    // --- Oracle Overrides ---
    // using chainlink for primary market oracle
    function _fetchPrimaryMarketOraclePrice() internal view override returns (Response memory) {
        return ChainlinkParser.getResponse(primaryMarketOracle.oracle);
    }

    // no fallback market oracle for wsteth/usd
    function _fetchFallbackMarketOraclePrice() internal view override returns (Response memory) {
        revert ("Fallback market oracle not supported");
    }

    // using chainlink for primary composite oracle
    function _fetchPrimaryCompositeOraclePrice() internal view override returns (Response memory) {
        return ChainlinkParser.getResponse(primaryCompositeOracle.oracle);
    }

    // using api3 for fallback composite oracle
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
