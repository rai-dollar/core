// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {PriceFeedBase} from "./PriceFeedBase.sol";
import {ChainlinkParser} from "./Parsers/ChainlinkParser.sol";
import {TellorParser} from "./Parsers/TellorParser.sol";
contract WETHPriceFeed is PriceFeedBase {
    // keccak256(abi.encode("SpotPrice", abi.encode("eth", "usd")));
    bytes32 public constant TELLOR_ETH_USD_QUERY_ID = 0x83a7f3d48786ac2667503a61e8c415438ed2922eb86a2906e4ee66d9a2ce4992; 

    constructor(OracleConfig memory _marketOracleConfig, address _token, uint256 _deviationThreshold) PriceFeedBase(_marketOracleConfig, _token, _deviationThreshold) {
    }

    function fetchPrice(bool _isRedemption) external override returns (uint256 price) {
        // if market price source is primary, fetch primary price
        if (marketPriceSource == PriceSource.primaryOracle) {
          Response memory primaryResponse = _getPrimaryMarketOracleResponse();
            if(primaryResponse.success) {
                _storeLastGoodMarketResponse(primaryResponse);
                return primaryResponse.price;
            } else {
                Response memory fallbackResponse = _getFallbackMarketOracleResponse();

                if(fallbackResponse.success) {
                    _storeLastGoodMarketResponse(fallbackResponse);
                    _setMarketPriceSource(PriceSource.fallbackOracle);
                    return fallbackResponse.price;
                } else {
                    _setMarketPriceSource(PriceSource.lastGoodResponse);
                }
            }
        }

        if(marketPriceSource == PriceSource.fallbackOracle) {
            Response memory primaryResponse = _getPrimaryMarketOracleResponse();
            Response memory fallbackResponse = _getFallbackMarketOracleResponse();

                bool isWithinDeviationThreshold = _withinDeviationThreshold(primaryResponse.price, fallbackResponse.price, deviationThreshold);
               
               // if prices are within deviation threshold, return chainlink price and set market price source to primary
                if(primaryResponse.success && fallbackResponse.success && isWithinDeviationThreshold) {          
                        _storeLastGoodMarketResponse(primaryResponse);
                        _setMarketPriceSource(PriceSource.primaryOracle);
                        return primaryResponse.price;
                        // if prices are deviated, return max of the two
                } else if(primaryResponse.success && fallbackResponse.success && !isWithinDeviationThreshold) {
                   bool returnPrimary = primaryResponse.price >= fallbackResponse.price ? true : false;
                   Response memory returnResponse = returnPrimary ? primaryResponse : fallbackResponse; 
                    _storeLastGoodMarketResponse(returnResponse);
                    // if primary price is returned, set market price source to primary
                    if(returnPrimary) {
                        _setMarketPriceSource(PriceSource.primaryOracle);
                    } 
                    // else keep using fallback
                    return returnResponse.price;
                } else if(!primaryResponse.success && fallbackResponse.success) {
                    _storeLastGoodMarketResponse(fallbackResponse);
                    _setMarketPriceSource(PriceSource.fallbackOracle);
                    return fallbackResponse.price;
                } else if (primaryResponse.success && !fallbackResponse.success) {
                    _storeLastGoodMarketResponse(primaryResponse);
                    _setMarketPriceSource(PriceSource.primaryOracle);
                    return primaryResponse.price;
                } else {
                    // if both are bad, set market price source to last good response
                    _setMarketPriceSource(PriceSource.lastGoodResponse);
                    return lastGoodMarketResponse.price;
                }
            }
            // Otherwise if branch is shut down and already using the lastGoodResponse, continue with it
            assert(marketPriceSource == PriceSource.lastGoodResponse);
            return lastGoodMarketResponse.price;
        }

    function _fetchPrimaryMarketOraclePrice() internal override returns (Response memory) {
        return ChainlinkParser.getResponse(primaryMarketOracle.oracle);
    }

    function _fetchFallbackMarketOraclePrice() internal override returns (Response memory) {
        return TellorParser.getResponse(fallbackMarketOracle.oracle, TELLOR_ETH_USD_QUERY_ID, fallbackMarketOracle.stalenessThreshold);
    }
    
    
}