// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {CompositePriceFeedBase} from "./CompositePriceFeedBase.sol";
import {ChainlinkParser} from "./Parsers/ChainlinkParser.sol";
import {Api3Parser} from "./Parsers/Api3Parser.sol";

interface IWSTEthRateProvider {
    function stEthPerToken() external view returns (uint256);
}

contract WSTETHPriceFeed is CompositePriceFeedBase {
    Response public lastGoodWstEthUsdResponse;

    event WstEthUsdResponseSaved(uint256 price, uint256 lastUpdated);
    event WstEthUsdPriceSourceChanged(PriceSource wethUsdPriceSource, uint256 timestamp);

    PriceSource public wethUsdPriceSource;
   constructor(OracleConfig memory _marketOracleConfig, OracleConfig memory _ethUsdOracleConfig, address _token, address _rateProvider, uint256 _deviationThreshold) CompositePriceFeedBase(_marketOracleConfig, _ethUsdOracleConfig, _token, _rateProvider, _deviationThreshold) {
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
        
        uint256 ethUsdStalenessThreshold = compositePriceSource == PriceSource.primaryOracle ? primaryCompositeOracle.stalenessThreshold : fallbackCompositeOracle.stalenessThreshold;
        bool ethUsdIsGood = isGoodResponse(ethUsdPriceResponse, ethUsdStalenessThreshold);

        uint256 stEthUsdStalenessThreshold = marketPriceSource == PriceSource.primaryOracle ? primaryMarketOracle.stalenessThreshold : fallbackMarketOracle.stalenessThreshold;
        bool stEthUsdIsGood = isGoodResponse(stEthUsdPriceResponse, stEthUsdStalenessThreshold);
        
        //if canonical rate fails or eth/usd is not good, shutdown everything
        if (!stethPerWstethResponse.success || !ethUsdIsGood ) {
            _setWethUsdPriceSource(PriceSource.lastGoodResponse);
            return lastGoodWstEthUsdResponse.price;
        }

        Response memory wstEthUsdResponse;
      
        // if market oracle and composite oracle are good, use the composite oracle price 
        if (stEthUsdIsGood && ethUsdIsGood) {
            bool withinDeviationThreshold = _withinDeviationThreshold(stEthUsdPriceResponse.price, ethUsdPriceResponse.price, deviationThreshold);
            // if redemption, check if the stEthUsdPrice and ethUsdPrice are within the deviation threshold
            if (_isRedemption && withinDeviationThreshold) {
                // if steth/usd and eth/usd are within the deviation threshold, use the redemption price
                    wstEthUsdResponse = _getMaxRedemptionPrice(stEthUsdPriceResponse, ethUsdPriceResponse, stethPerWstethResponse);
                
            } else if (_isRedemption && !withinDeviationThreshold) {
                // if not within the deviation threshold, use eth/usd price for calculation
                wstEthUsdResponse.price = _getRedemptionPrice(ethUsdPriceResponse.price, stethPerWstethResponse.price);
                wstEthUsdResponse.success = ethUsdPriceResponse.success && stethPerWstethResponse.success;
                wstEthUsdResponse.lastUpdated = stethPerWstethResponse.lastUpdated;

            } else if (!_isRedemption && withinDeviationThreshold) {
                // if not a redemption and within the deviation threshold, use steth/usd price for calculation
                wstEthUsdResponse.price = _getRedemptionPrice(stEthUsdPriceResponse.price, stethPerWstethResponse.price);
                wstEthUsdResponse.success = stEthUsdPriceResponse.success && stethPerWstethResponse.success;
                wstEthUsdResponse.lastUpdated = stethPerWstethResponse.lastUpdated;

            } else {
                // if not redemption and not within the deviation threshold, use eth/usd price for calculation
                wstEthUsdResponse.price = ethUsdPriceResponse.price * stethPerWstethResponse.price / 1e18;
                wstEthUsdResponse.success = ethUsdPriceResponse.success && stethPerWstethResponse.success;
            }
            // if the wsteth/usd price is good, save it if not, shutdown and return last good response
            if (isGoodResponse(wstEthUsdResponse, ethUsdStalenessThreshold)) {
                _saveLastGoodWstEthUsdResponse(wstEthUsdResponse);
            } else {
                _setWethUsdPriceSource(PriceSource.lastGoodResponse);
                wstEthUsdResponse = lastGoodWstEthUsdResponse;  
            }
        } else {
            _setWethUsdPriceSource(PriceSource.lastGoodResponse);
            wstEthUsdResponse = lastGoodWstEthUsdResponse;  
        }

        // @bkellerman leaving this commented, we could add this or something like it if we wanted to have some fallback logic
        // in case of the failure of the StethUsd oracle (which is not entirely neccessary)
        // and assume eth and steth should always be pegged

        // } else if (!stEthUsdIsGood && ethUsdIsGood) {
        //     // if market oracle is not good and composite oracle is good, use the composite oracle price
        //     wstEthUsdResponse.price = _getRedemptionPrice(ethUsdPriceResponse.price, stethPerWstethResponse.price);
        //     wstEthUsdResponse.success = false;
        //     wstEthUsdResponse.lastUpdated = ethUsdPriceResponse.timestamp;
        // } else {
        //     //return last good response and shut down everything
        //     _setWethUsdPriceSource(PriceSource.lastGoodResponse);
        //     wstEthUsdResponse = lastGoodWstEthUsdResponse;      
        // }

        return wstEthUsdResponse.price;
    }

    function _fetchMarketOracleStEthUsdPrice() internal returns (Response memory _stEthUsdPriceResponse) {
        if(marketPriceSource == PriceSource.lastGoodResponse) {
            return lastGoodMarketResponse;
        }

        // fetch stethUsdPrice from primary market oracle
        Response memory stEthUsdPriceResponse = _fetchPrimaryMarketOraclePrice();

        if (isGoodResponse(stEthUsdPriceResponse, primaryMarketOracle.stalenessThreshold)) {
            _storeLastGoodMarketResponse(stEthUsdPriceResponse);
            _stEthUsdPriceResponse = stEthUsdPriceResponse;
        } else {
            _setMarketPriceSource(PriceSource.lastGoodResponse);
            _stEthUsdPriceResponse = lastGoodMarketResponse;
            _stEthUsdPriceResponse.success = false;
        }

        return _stEthUsdPriceResponse;
    }

    function _fetchEthUsdPrice() internal returns (Response memory _ethUsdPriceResponse) {
        if(compositePriceSource == PriceSource.lastGoodResponse) {
            return lastGoodCompositeResponse;
        }

        if(compositePriceSource == PriceSource.primaryOracle) {
            // fetch ethUsdPrice from primary oracle
            Response memory ethUsdPriceResponse = _fetchPrimaryCompositeOraclePrice();

            // if the primary ethUsdPrice is good, save it and return it
        if (isGoodResponse(ethUsdPriceResponse, primaryCompositeOracle.stalenessThreshold)) {
            _storeLastGoodCompositeResponse(ethUsdPriceResponse);
            _ethUsdPriceResponse = ethUsdPriceResponse;

        } else {
            // if the ethUsdPrice is not good, check if the fallback oracle is good
            Response memory ethUsdPriceResponseFallback = _fetchFallbackCompositeOraclePrice();

            // if the fallback ethUsdPrice is good, save it, set price source to fallback and return it
            if (isGoodResponse(ethUsdPriceResponseFallback, fallbackCompositeOracle.stalenessThreshold)) {
                _setCompositePriceSource(PriceSource.fallbackOracle);
                _storeLastGoodCompositeResponse(ethUsdPriceResponseFallback);
                _ethUsdPriceResponse = ethUsdPriceResponseFallback;
                // if the fallback ethUsdPrice is not good, set price source to last good and return last good response
            } else {
                _setCompositePriceSource(PriceSource.lastGoodResponse);
                _ethUsdPriceResponse = lastGoodCompositeResponse;
                _ethUsdPriceResponse.success = false;
                }
            }
        } 
        
        if (compositePriceSource == PriceSource.fallbackOracle) {
           Response memory ethUsdPriceResponseFallback = _fetchFallbackCompositeOraclePrice();
           bool fallbackIsGood = isGoodResponse(ethUsdPriceResponseFallback, fallbackCompositeOracle.stalenessThreshold);

           Response memory ethUsdPriceResponse = _fetchPrimaryCompositeOraclePrice();
           bool primaryIsGood = isGoodResponse(ethUsdPriceResponse, primaryCompositeOracle.stalenessThreshold) && 
           _withinDeviationThreshold(ethUsdPriceResponse.price, ethUsdPriceResponseFallback.price, deviationThreshold);

           // if primary oracle is now good and fallback is good set composite price source to primary 
           // and return max of the two responses
           if (primaryIsGood && fallbackIsGood) {
                _setCompositePriceSource(PriceSource.primaryOracle);

                // return the max of the two responses
                _ethUsdPriceResponse = ethUsdPriceResponse.price > ethUsdPriceResponseFallback.price ? ethUsdPriceResponse : ethUsdPriceResponseFallback;

                _storeLastGoodCompositeResponse(_ethUsdPriceResponse);

           } else if (!primaryIsGood && fallbackIsGood) {
                // if primary is not good and fallback is good, return fallback response
                _storeLastGoodCompositeResponse(ethUsdPriceResponseFallback);
                _ethUsdPriceResponse = ethUsdPriceResponseFallback;
           } else {
                // if both are not good, return last good response
                _setCompositePriceSource(PriceSource.lastGoodResponse);
                _ethUsdPriceResponse = lastGoodCompositeResponse;
                _ethUsdPriceResponse.success = false;
           }
        } 

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
                // if wethUsdPriceSource is lastGoodResponse, set composite and market price source to lastGoodResponse
                if (wethUsdPriceSource == PriceSource.lastGoodResponse) {
                    _setCompositePriceSource(PriceSource.lastGoodResponse);
                    _setMarketPriceSource(PriceSource.lastGoodResponse);
                    emit ShutdownInitiated("Weth Usd Price Source Failure", block.timestamp);
                }
        }
    }
}
