// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {CompositePriceFeedBase} from "./CompositePriceFeedBase.sol";
import {ChainlinkParser} from "./Parsers/ChainlinkParser.sol";
import {Api3Parser} from "./Parsers/Api3Parser.sol";
import {Constants as C} from "./Common/Constants.sol";
import {LiquityMath} from "./Common/LiquityMath.sol";

interface IWSTEthRateProvider {
    function getRate() external view returns (uint256);
}

contract WSTETHPriceFeed is CompositePriceFeedBase {
    Response public lastGoodWstEthUsdResponse;

    event LastGoodWstEthUsdResponse(Oracle ethUsdOracle, uint256 price, uint256 lastUpdated);
    
   constructor(OracleConfig memory _marketOracleConfig, OracleConfig memory _ethUsdOracleConfig, address _token, address _rateProvider) CompositePriceFeedBase(_marketOracleConfig, _ethUsdOracleConfig, _token, _rateProvider) {}


function fetchPrice(bool _isRedemption) external override returns (uint256 price) {
        Response memory stEthUsdPriceResponse = _fetchMarketOraclePrice();
        Response memory ethUsdPriceResponse = _fetchEthUsdPrice();
        Response memory stethPerWstethResponse = _fetchCanonicalstEthPerWstethRate();

        if (!stethPerWstethResponse.success) {
            _setEthUsdPriceSource(PriceSource.lastGoodResponse);
            return lastGoodEthUsdResponse.price;
        }

        // Otherwise, use the primary price calculation:
        Response memory wstEthUsdResponse;


        if (_isRedemption && _withinDeviationThreshold(stEthUsdPriceResponse.price, ethUsdPriceResponse.price, C.STETH_USD_DEVIATION_THRESHOLD)) {
            wstEthUsdResponse = _getRedemptionPrice(stEthUsdPriceResponse, ethUsdPriceResponse, stethPerWstethResponse);
        } else {
            wstEthUsdResponse.price = stEthUsdPriceResponse.price * stethPerWstethResponse.price / 1e18;
            wstEthUsdResponse.success = true;
            wstEthUsdResponse.lastUpdated = block.timestamp;
        }

        if (isGoodResponse(wstEthUsdResponse, ethUsdOracle.stalenessThreshold)) {
            _saveLastGoodEthUsdResponse(wstEthUsdResponse);
        } else {
            wstEthUsdResponse = lastGoodWstEthUsdResponse;  
        }

        return wstEthUsdResponse.price;
    }

    // --- Oracle Overrides ---

    function _fetchPriceFromPrimaryOracle() internal view override returns (Response memory) {
        return ChainlinkParser.getResponse(primaryOracle.oracle);
    }

    function _fetchPriceFromFallbackOracle() internal view override returns (Response memory) {
        return Api3Parser.getResponse(fallbackOracle.oracle);
    }

    function _fetchPrimaryEthUsdPrice() internal view override returns (Response memory) {
        return ChainlinkParser.getResponse(ethUsdOracle.oracle);
    }

    function _fetchFallbackEthUsdPrice() internal view override returns (Response memory) {
        return Api3Parser.getResponse(ethUsdOracleFallback.oracle);
    }

    function _fetchCanonicalstEthPerWstethRate() internal view returns (Response memory response) {
        Response memory canonicalRateResponse = _fetchCanonicalRate();

        if (!canonicalRateResponse.success) {
            return response;
        }

        return canonicalRateResponse;
    }

    function _fetchCanonicalRate() internal override view returns (Response memory response) {
        uint256 gasBefore = gasleft();

        try IWSTEthRateProvider(rateProvider).getRate() returns (uint256 stEthPerWstEth) {
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


            // If call to exchange rate reverted for another reason, return true
            return response;
        }
    }

    function _saveLastGoodWstEthUsdResponse(Response memory _response) internal {
        if (_response.success) {
            lastGoodWstEthUsdResponse = _response;
            emit LastGoodWstEthUsdResponse(ethUsdOracle, _response.price, _response.lastUpdated);
        }
    }
    
}