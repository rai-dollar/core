// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../Interfaces/AggregatorV3Interface.sol";
import "../Common/LiquityMath.sol";
import {Constants as C} from "../Common/Constants.sol";
import "../Interfaces/IPriceFeed.sol";

/*
* this library is used to parse the response from the Chainlink oracle and convert it to the Response struct
*/

library ChainlinkParser {
    struct ChainlinkResponse {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    function getResponse(address _chainlinkOracle) public view returns (IPriceFeed.Response memory response) {
        ChainlinkResponse memory chainlinkResponse;
        AggregatorV3Interface chainlinkOracle = AggregatorV3Interface(_chainlinkOracle);

        uint8 decimals = _getOracleDecimals(chainlinkOracle);

        uint256 gasBefore = gasleft();
        try chainlinkOracle.latestRoundData() returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
            chainlinkResponse.roundId = roundId;
            chainlinkResponse.answer = answer;
            chainlinkResponse.startedAt = startedAt;
            chainlinkResponse.updatedAt = updatedAt;
            chainlinkResponse.answeredInRound = answeredInRound;

            uint256 convertedPrice = _convertDecimals(chainlinkResponse.answer, decimals);
            response.price = convertedPrice;
            response.lastUpdated = chainlinkResponse.updatedAt;
 
            if (isGoodResponse(response)) {
                response.success = true;

                return response;
            } else {

                return response;
            }
        } catch {
            // Require that enough gas was provided to prevent an OOG revert in the call to Chainlink
            // causing a shutdown. Instead, just revert. Slightly conservative, as it includes gas used
            // in the check itself.
            if (gasleft() <= gasBefore / 64) revert IPriceFeed.InsufficientGasForExternalCall();


            return response;
        }
    }
    
    // gets the decimals and asserts that the passed in oracle is a valid Chainlink oracle
    function _getOracleDecimals(AggregatorV3Interface _chainlinkOracle) internal view returns (uint8) {
        uint8 decimals = _chainlinkOracle.decimals();
        assert(decimals == 8);
        return decimals;
    }
    
    function _convertDecimals(int256 price, uint8 decimals) internal pure returns (uint256) {
        if (price < 0) {
            revert("Chainlink price is negative");
        }
        return uint256(price) * 10 ** (18 - decimals);
    }

    function isStale(uint256 lastUpdated) public view returns (bool) {
        return block.timestamp - lastUpdated > C.CHAINLINK_STALENESS_THRESHOLD;
    }

    function isGoodResponse(IPriceFeed.Response memory _response) public view returns (bool) {
        return _response.success && _response.price > 0 && _response.lastUpdated > 0 && !isStale(_response.lastUpdated);
    }

    function deviationThreshold() public pure returns (uint256) {
        return C.CHAINLINK_MAX_PRICE_DEVIATION;
    }
}