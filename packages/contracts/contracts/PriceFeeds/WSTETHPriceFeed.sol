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

contract WSTETHPriceFeed is CompositePriceFeedBase, ChainlinkParser, Api3Parser {
    constructor(address _primaryOracle, address _fallbackOracle, address _token, address _rateProvider, address _ethUsdOracle) CompositePriceFeedBase(_primaryOracle, _fallbackOracle, _token, _rateProvider, _ethUsdOracle) {}


function fetchPrice(bool _isRedemption) external override returns (uint256 price, bool success) {
        Response memory stEthUsdPriceResponse = _fetchTokenOraclePrice();

        Response memory ethUsdPriceResponse = _fetchEthUsdPrice();
        (uint256 stEthUsdRate, bool stEthUsdRateSuccess) = _fetchCanonicalRate();

        if (!stEthUsdPriceResponse.success || !stEthUsdRateSuccess) {
            return (0, false);
        }

        // Otherwise, use the primary price calculation:
        uint256 wstEthUsdPrice;

        if (_isRedemption && _withinDeviationThreshold(stEthUsdPrice, stEthUsdRate, C.STETH_USD_DEVIATION_THRESHOLD)) {
            // If it's a redemption and within 1%, take the max of (STETH-USD, ETH-USD) to mitigate unwanted redemption arb and convert to WSTETH-USD
            wstEthUsdPrice = LiquityMath._max(stEthUsdPrice, stEthUsdRate);
        } else {
            // Otherwise, just calculate WSTETH-USD price: USD_per_WSTETH = USD_per_STETH * STETH_per_WSTETH
            wstEthUsdPrice = stEthUsdPrice * stEthUsdRate / 1e18;
        }

        lastGoodPrice = wstEthUsdPrice;

        return (wstEthUsdPrice, true);

    }
    // --- Oracle Overrides ---

    function _fetchPriceFromPrimaryOracle() internal override returns (Response memory) {
        return getChainlinkResponse(primaryOracle);
    }

    function _fetchPriceFromFallbackOracle() internal override returns (Response memory) {
        return getApi3Response(fallbackOracle);
    }

    function _fetchEthUsdPrice() internal view returns (Response memory) {
        return getChainlinkResponse(ethUsdOracle);
    }
    
    function _fetchCanonicalStEthUsdPrice() internal view returns (Response memory response) {
        Response memory ethUsdPriceResponse = _fetchEthUsdPrice();
        bool isGoodEthUsdPrice = isGoodResponse(ethUsdPriceResponse, chainlinkStalenessThreshold());
        (uint256 canonicalRate, bool canonicalRateSuccess) = _fetchCanonicalRate();

        if (!isGoodEthUsdPrice || !canonicalRateSuccess) {
            return response;
        }

        uint256 stEthUsdPrice = _canonicalStEthUsdPrice(canonicalRate, ethUsdPriceResponse.price);

        response.price = stEthUsdPrice;
        response.lastUpdated = ethUsdPriceResponse.lastUpdated;
        response.success = true;

        return response;
    }

    function _canonicalStEthUsdPrice(uint256 _canonicalRate, uint256 _ethUsdPrice) internal view returns (uint256 stEthUsdPrice) {
        stEthUsdPrice = _ethUsdPrice * _canonicalRate / 1e18;

        return stEthUsdPrice;
    }

    function _fetchCanonicalRate() internal view returns (uint256, bool) {
        uint256 gasBefore = gasleft();

        try IWSTEthRateProvider(rateProvider).getRate() returns (uint256 stEthPerWstEth) {
            // If rate is 0, return true
            if (stEthPerWstEth == 0) return (0, false);

            return (stEthPerWstEth, true);
        } catch {
            // Require that enough gas was provided to prevent an OOG revert in the external call
            // causing a shutdown. Instead, just revert. Slightly conservative, as it includes gas used
            // in the check itself.
            if (gasleft() <= gasBefore / 64) revert InsufficientGasForExternalCall();


            // If call to exchange rate reverted for another reason, return true
            return (0, true);
        }
    }

    // --- Threshold Overrides ---

    function _primaryStalenessThreshold() internal pure override returns (uint256) {
        return C.PRIMARY_STALENESS_THRESHOLD;
    }

    function _fallbackStalenessThreshold() internal pure override returns (uint256) {
        return Api3Parser.stalenessThreshold();
    }

    function _deviationThreshold() internal pure override returns (uint256) {
        return C.WSTETH_DEVIATION_THRESHOLD;
    }

    
}