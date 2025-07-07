// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {PriceFeedBase} from "./PriceFeedBase.sol";
import {ChainlinkParser} from "./Parsers/ChainlinkParser.sol";
import {TellorParser} from "./Parsers/TellorParser.sol";
contract WETHPriceFeed is PriceFeedBase {
    address public primaryOracle;
    address public fallbackOracle;
    uint256 public primaryStalenessThreshold;
    uint256 public fallbackStalenessThreshold;
    uint256 public deviationThreshold;
    address public weth;

    // keccak256(abi.encode("SpotPrice", abi.encode("eth", "usd")));
    bytes32 public constant TELLOR_ETH_USD_QUERY_ID = 0x83a7f3d48786ac2667503a61e8c415438ed2922eb86a2906e4ee66d9a2ce4992; 

    constructor(OracleConfig memory _marketOracleConfig, address _token, uint256 _deviationThreshold) PriceFeedBase(_marketAggregator, _fallbackAggregator, _weth, _wethUsd) {

        primaryOracle = _marketOracleConfig.primaryOracle;
        fallbackOracle = _marketOracleConfig.fallbackOracle;
        weth = _token;
        primaryStalenessThreshold = _marketOracleConfig.primaryStalenessThreshold;
        fallbackStalenessThreshold = _marketOracleConfig.fallbackStalenessThreshold;
        deviationThreshold = _deviationThreshold;
    }

    function fetchPrice(bool _isRedemption) external override returns (uint256 price) {
        // if market price source is primary, fetch primary price
        if (marketPriceSource == PriceSource.primary) {
          Response memory primaryResponse = _fetchPrimaryMarketOraclePrice();
            bool primaryIsGood = isGoodResponse(primaryResponse, primaryStalenessThreshold);
            
            if(primaryIsGood) {
                _storeLastGoodMarketResponse(primaryResponse);
                return primaryResponse.price;
            } else {
                Response memory fallbackResponse = _fetchFallbackMarketOraclePrice();
                bool fallbackIsGood = isGoodResponse(fallbackResponse, fallbackStalenessThreshold);

                if(fallbackIsGood) {
                    _storeLastGoodMarketResponse(fallbackResponse);
                    _setMarketPriceSource(PriceSource.fallback);
                    return fallbackResponse.price;
                } else {
                    _setMarketPriceSource(PriceSource.lastGoodResponse);
                }
            }

        // if market price source is fallback, fetch primary and fallback prices
        } else if (marketPriceSource == PriceSource.fallback) {
            Response memory primaryResponse = _fetchPrimaryMarketOraclePrice();
            bool primaryIsGood = isGoodResponse(primaryResponse, primaryStalenessThreshold);
            Response memory fallbackResponse = _fetchFallbackMarketOraclePrice();

            bool fallbackIsGood = isGoodResponse(fallbackResponse, fallbackStalenessThreshold);
            bool isWithinDeviationThreshold = _withinDeviationThreshold(primaryResponse.price, fallbackResponse.price, deviationThreshold);
               
               // if prices are within deviation threshold, return chainlink price and set market price source to primary
                if(primaryIsGood && fallbackIsGood && isWithinDeviationThreshold) {          
                        _storeLastGoodMarketResponse(returnResponse);
                        _setMarketPriceSource(PriceSource.primary);
                        return returnResponse.price;
                        // if prices are deviated, return max of the two
                } else if(primaryIsGood && fallbackIsGood && !isWithinDeviationThreshold) {
                   bool returnPrimary = primaryResponse.price >= fallbackResponse.price ? true : false;
                   Response memory returnResponse = returnPrimary ? primaryResponse : fallbackResponse; 
                    _storeLastGoodMarketResponse(returnResponse);
                    // if primary price is returned, set market price source to primary
                    if(returnPrimary) {
                        _setMarketPriceSource(PriceSource.primary);
                    } 
                    // else keep using fallback
                    return returnResponse.price;
                } else if(!primaryIsGood && fallbackIsGood) {
                    _storeLastGoodMarketResponse(fallbackResponse);
                    _setMarketPriceSource(PriceSource.fallback);
                    return fallbackResponse.price;
                } else if (primaryIsGood && !fallbackIsGood) {
                    _storeLastGoodMarketResponse(primaryResponse);
                    _setMarketPriceSource(PriceSource.primary);
                    return primaryResponse.price;
                } else {
                    // if both are bad, set market price source to last good response
                    _setMarketPriceSource(PriceSource.lastGoodResponse);
                }
            }
            // Otherwise if branch is shut down and already using the lastGoodResponse, continue with it
            assert(marketPriceSource == PriceSource.lastGoodResponse);
            return lastGoodMarketResponse.price;
        }

    function _fetchPrimaryMarketOraclePrice() internal override returns (Response memory) {
        return ChainlinkParser.getResponse(primaryOracle, primaryStalenessThreshold);
    }

    function _fetchFallbackMarketOraclePrice() internal override returns (Response memory) {
        return TellorParser.getResponse(fallbackOracle, TELLOR_ETH_USD_QUERY_ID, fallbackStalenessThreshold);
    }
    
    
}