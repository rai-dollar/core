// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "../Interfaces/IPriceFeed.sol";
import {Constants as C} from "../Common/Constants.sol";
import "../Interfaces/AggregatorV3Interface.sol";

/*
* this library is used to parse the response from the Redstone oracle and convert it to the Response struct
*/

library RedstoneParser {
    struct RedstoneResponse {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    error InvalidRedstoneResponse();

    function getResponse(address _redstoneOracle) internal view returns (IPriceFeed.Response memory response) {
        AggregatorV3Interface redstoneOracle = AggregatorV3Interface(_redstoneOracle);
        RedstoneResponse memory redstoneResponse;
        uint8 decimals = _getOracleDecimals(redstoneOracle);

        uint256 gasBefore = gasleft();
        try AggregatorV3Interface(_redstoneOracle).latestRoundData() returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
            redstoneResponse.roundId = roundId;
            redstoneResponse.answer = answer;
            redstoneResponse.startedAt = startedAt;
            redstoneResponse.updatedAt = updatedAt;
            redstoneResponse.answeredInRound = answeredInRound;

            uint256 convertedPrice = _convertDecimals(redstoneResponse.answer, decimals);
            response.price = convertedPrice;
            response.lastUpdated = redstoneResponse.updatedAt;
            response.success = response.lastUpdated != 0 && response.price != 0;

            return response;
        } catch {
            // Require that enough gas was provided to prevent an OOG revert in the call to Chainlink
            // causing a shutdown. Instead, just revert. Slightly conservative, as it includes gas used
            // in the check itself.
            if (gasleft() <= gasBefore / 64) revert IPriceFeed.InsufficientGasForExternalCall();


            return response;
        }

        if(redstoneResponse.answer <= 0) {
            revert InvalidRedstoneResponse();
        }

        // cast int response to uint256 a negative value will revert
        response.price = uint256(redstoneResponse.answer);
        response.lastUpdated = redstoneResponse.updatedAt;
        response.success = true;

        return response;
    }

    function _convertDecimals(int256 _answer, uint8 _decimals) internal pure returns (uint256) {
        return uint256(_answer) * 10 ** (18 - _decimals);
    }

    function _getOracleDecimals(AggregatorV3Interface _redstoneOracle) internal view returns (uint8) {
        uint8 decimals = _redstoneOracle.decimals();
        assert(decimals != 0);
        return decimals;
    }
}