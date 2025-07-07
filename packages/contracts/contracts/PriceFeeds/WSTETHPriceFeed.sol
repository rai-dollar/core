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
    Response public lastGoodWstEthUsdResponse;

    event WstEthUsdResponseSaved(uint256 price, uint256 lastUpdated);
    event WstEthUsdPriceSourceChanged(PriceSource wethUsdPriceSource, uint256 timestamp);

    PriceSource public wethUsdPriceSource;
   constructor(
    OracleConfig memory _marketOracleConfig, 
    OracleConfig memory _ethUsdOracleConfig, 
    address _token, 
    address _rateProvider, 
    uint256 _deviationThreshold,
    uint256 _wethUsdStalenessThreshold
    ) CompositePriceFeedBase(_marketOracleConfig, _ethUsdOracleConfig, _token, _rateProvider, _deviationThreshold) {
    // we are only using one stEth/usd oracle
    require(_marketPrimaryIsSet(), "Primary market oracle must be set");
    // there should be a primary and fallback eth/usd oracle
    require(_compositePrimaryIsSet(), "Eth usd primary oracle must be set");
    require(_compositeFallbackIsSet(), "Eth usd fallback oracle must be set");
   }


function fetchPrice(bool _isRedemption) external override returns (uint256 price) {
    if (wethUsdPriceSource == PriceSource.lastGoodResponse) {
        return lastGoodWstEthUsdResponse.price;
    }

        Response memory stEthUsdPriceResponse = _fetchMarketOracleStEthUsdPrice();
        Response memory ethUsdPriceResponse = _fetchEthUsdPrice();
        Response memory stethPerWstethResponse = _fetchCanonicalstEthPerWstethRate();

        //if canonical rate fails or eth/usd is not good, shutdown everything
        if (!stethPerWstethResponse.success || !ethUsdPriceResponse.success) {
            _setWethUsdPriceSource(PriceSource.lastGoodResponse);
            return lastGoodWstEthUsdResponse.price;
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
                _saveLastGoodWstEthUsdResponse(wstEthUsdResponse);
            } else {
                _setWethUsdPriceSource(PriceSource.lastGoodResponse);
                wstEthUsdResponse = lastGoodWstEthUsdResponse;  
                wstEthUsdResponse.success = false;
            }
        } else if (!stEthUsdPriceResponse.success && ethUsdPriceResponse.success) {
            // if market oracle is not good and composite oracle is good, use the eth/usd price and use fallback
            wstEthUsdResponse.price = _getRedemptionPrice(ethUsdPriceResponse.price, stethPerWstethResponse.price);
            wstEthUsdResponse.success = false;
            wstEthUsdResponse.lastUpdated = ethUsdPriceResponse.lastUpdated;

            _saveLastGoodWstEthUsdResponse(wstEthUsdResponse);

            _setWethUsdPriceSource(PriceSource.fallbackOracle);
        } else {
            //return last good response and use last good response for everything
            _setWethUsdPriceSource(PriceSource.lastGoodResponse);
            wstEthUsdResponse = lastGoodWstEthUsdResponse;  
            wstEthUsdResponse.success = false;
        }

        return wstEthUsdResponse.price;
    }

    function _fetchMarketOracleStEthUsdPrice() internal returns (Response memory) {
        // fetch stethUsdPrice from primary market oracle
        if(marketPriceSource == PriceSource.primaryOracle) {
            Response memory stEthUsdPriceResponse = _getPrimaryMarketOracleResponse();
            if (stEthUsdPriceResponse.success) {
                return stEthUsdPriceResponse;
            } else {
                _setMarketPriceSource(PriceSource.lastGoodResponse);
                return lastGoodMarketResponse;
            }
        } 

        assert(marketPriceSource == PriceSource.lastGoodResponse);
        return lastGoodMarketResponse;
    }

    function _fetchEthUsdPrice() internal returns (Response memory _ethUsdPriceResponse) {
        if(compositePriceSource == PriceSource.primaryOracle) {
            // fetch ethUsdPrice from primary oracle
            Response memory ethUsdPriceResponse = _getPrimaryCompositeOracleResponse();

            // if the primary ethUsdPrice is good, save it and return it
            if (ethUsdPriceResponse.success) {
                return ethUsdPriceResponse;

            } else {
                // if the ethUsdPrice is not good, check if the fallback oracle is good
                Response memory ethUsdPriceResponseFallback = _getFallbackCompositeOracleResponse();
                // if the fallback ethUsdPrice is good, save it, set price source to fallback and return it
                if (ethUsdPriceResponseFallback.success) {
                    _setCompositePriceSource(PriceSource.fallbackOracle);
                    return ethUsdPriceResponseFallback;
                    // if the fallback ethUsdPrice is not good, set price source to last good and return last good response
                } else {
                    _setCompositePriceSource(PriceSource.lastGoodResponse);
                    return lastGoodCompositeResponse;
                }
            }
        } 
        
        if (compositePriceSource == PriceSource.fallbackOracle) {
           Response memory ethUsdPriceResponseFallback = _getFallbackCompositeOracleResponse();
           Response memory ethUsdPriceResponse = _getPrimaryCompositeOracleResponse();

           bool primaryIsGood = ethUsdPriceResponse.success && 
           _withinDeviationThreshold(ethUsdPriceResponse.price, ethUsdPriceResponseFallback.price, deviationThreshold);

           // if primary oracle is now good and fallback is good set composite price source to primary 
           // and return max of the two responses
           if (primaryIsGood && ethUsdPriceResponseFallback.success) {
                _setCompositePriceSource(PriceSource.primaryOracle);

                // return the max of the two responses
                 Response memory ethUsdPriceResponse = ethUsdPriceResponse.price > ethUsdPriceResponseFallback.price ? ethUsdPriceResponse : ethUsdPriceResponseFallback;
                return ethUsdPriceResponse;

           } else if (!primaryIsGood && ethUsdPriceResponseFallback.success) {
                return ethUsdPriceResponseFallback;
           } else {
                // if both are not good, return empty response since response is not stored lastGood will be empty
                _setCompositePriceSource(PriceSource.lastGoodResponse);
                return lastGoodCompositeResponse;
           }
        } 

        assert(compositePriceSource == PriceSource.lastGoodResponse);
        // since we're not storing the primary or composite oracle responses, lastGood will be empty indicating a failure
        return lastGoodCompositeResponse;
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

    function _fetchCanonicalstEthPerWstethRate() internal view returns (Response memory response) {
        Response memory canonicalRateResponse = _fetchCanonicalRate();

        if (!canonicalRateResponse.success) {
            return response;
        }

        return canonicalRateResponse;
    }

    function _fetchCanonicalRate() internal override view returns (Response memory response) {
        uint256 gasBefore = gasleft();

        try IWSTEthRateProvider(rateProvider).stEthPerToken() returns (uint256 stEthPerWstEth) {
            // If rate is 0, return true
            if (stEthPerWstEth == 0) return response;
            response.price = stEthPerWstEth;
            response.success = true;
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

    function _saveLastGoodWstEthUsdResponse(Response memory _response) internal {
        if (_response.success) {
            lastGoodWstEthUsdResponse = _response;
            emit WstEthUsdResponseSaved(_response.price, _response.lastUpdated);
        }
    }

    function _setWethUsdPriceSource(PriceSource _wethUsdPriceSource) internal {
        if (wethUsdPriceSource != _wethUsdPriceSource) {
            wethUsdPriceSource = _wethUsdPriceSource;
            emit WstEthUsdPriceSourceChanged(_wethUsdPriceSource, block.timestamp);
                // if wethUsdPriceSource is lastGoodResponse, shut down price feed
                if (wethUsdPriceSource == PriceSource.lastGoodResponse) {
                    _shutdownAndSwitchToLastGoodWstEthUsdResponse();
                }
        }
    }

    function _shutdownAndSwitchToLastGoodWstEthUsdResponse() internal {
        lastGoodWstEthUsdResponse.success = false;
        emit ShutdownInitiated("WstEth Usd Price Source Failure", block.timestamp);
    }

}
